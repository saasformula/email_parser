defmodule EmailParser.ContentType do
  @moduledoc false
  # Parses `Content-Type` and `Content-Disposition` header values into a type,
  # an optional subtype and a list of parameters.
  #
  # Handles quoted-string and token parameter values, RFC 2231 extended
  # parameters and continuations (`filename*0*=utf-8''...`), and RFC 2047
  # encoded words inside parameter values. Type, subtype and parameter names
  # are downcased; parameter values keep their case.

  alias EmailParser.{Charset, EncodedWord}

  defstruct type: "", subtype: nil, params: []

  @type t :: %__MODULE__{
          type: String.t(),
          subtype: String.t() | nil,
          params: [{String.t(), String.t()}]
        }

  @spec parse(String.t()) :: t | nil
  def parse(value) when is_binary(value) do
    {type_part, params_part} =
      case :binary.split(value, ";") do
        [type_part, params_part] -> {type_part, params_part}
        [type_part] -> {type_part, ""}
      end

    {type, subtype} =
      case :binary.split(type_part, "/") do
        [type, subtype] -> {normalize_token(type), normalize_token(subtype)}
        [type] -> {normalize_token(type), nil}
      end

    if type == "" do
      nil
    else
      params =
        params_part
        |> parse_params([])
        |> resolve_rfc2231()
        |> Enum.map(fn {name, value} -> {name, decode_encoded_words(value)} end)

      %__MODULE__{type: type, subtype: presence(subtype), params: params}
    end
  end

  @doc "Returns the value of parameter `name`, or `nil` when absent."
  @spec param(t | nil, String.t()) :: String.t() | nil
  def param(nil, _name), do: nil

  def param(%__MODULE__{params: params}, name) do
    Enum.find_value(params, fn
      {^name, value} -> value
      _other -> nil
    end)
  end

  @spec has_param?(t | nil, String.t()) :: boolean
  def has_param?(content_type, name), do: param(content_type, name) != nil

  defp normalize_token(token), do: token |> String.trim() |> String.downcase(:ascii)

  defp presence(""), do: nil
  defp presence(other), do: other

  defp decode_encoded_words(value) do
    if String.contains?(value, "=?"), do: EncodedWord.decode(value), else: value
  end

  ## Parameter tokenizer

  defp parse_params(rest, acc) do
    case skip_separators(rest) do
      "" ->
        Enum.reverse(acc)

      rest ->
        case :binary.match(rest, ["=", ";"]) do
          :nomatch ->
            finish_param(acc, rest, "")

          {pos, 1} ->
            <<name::binary-size(^pos), sep, rest::binary>> = rest

            case sep do
              ?; -> parse_params(rest, push_param(acc, name, ""))
              ?= -> parse_value(rest, name, acc)
            end
        end
    end
  end

  defp parse_value(rest, name, acc) do
    case String.trim_leading(rest) do
      "\"" <> quoted ->
        {value, rest} = take_quoted(quoted, [])
        parse_params(skip_to_separator(rest), push_param(acc, name, value))

      rest ->
        case :binary.split(rest, ";") do
          [value, rest] -> parse_params(rest, push_param(acc, name, String.trim(value)))
          [value] -> finish_param(acc, name, String.trim(value))
        end
    end
  end

  defp finish_param(acc, name, value), do: Enum.reverse(push_param(acc, name, value))

  defp push_param(acc, name, value) do
    case name |> String.trim() |> String.downcase(:ascii) do
      "" -> acc
      name -> [{name, value} | acc]
    end
  end

  defp take_quoted("", acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), ""}
  defp take_quoted("\"" <> rest, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  defp take_quoted(<<"\\", char, rest::binary>>, acc), do: take_quoted(rest, [<<char>> | acc])
  defp take_quoted(<<char, rest::binary>>, acc), do: take_quoted(rest, [<<char>> | acc])

  defp skip_separators(<<char, rest::binary>>) when char in [?;, ?\s, ?\t, ?\r, ?\n],
    do: skip_separators(rest)

  defp skip_separators(rest), do: rest

  # After a closing quote, anything up to the next `;` is ignored.
  defp skip_to_separator(rest) do
    case :binary.split(rest, ";") do
      [_junk, rest] -> rest
      [_junk] -> ""
    end
  end

  ## RFC 2231 extended parameters and continuations

  defp resolve_rfc2231(params) do
    if Enum.any?(params, fn {name, _value} -> String.ends_with?(name, "*") or section?(name) end) do
      params
      |> Enum.map(&classify_rfc2231/1)
      |> merge_rfc2231([])
    else
      params
    end
  end

  defp section?(name) do
    case Regex.run(~r/^(.+)\*\d+\*?$/, name) do
      nil -> false
      _match -> true
    end
  end

  defp classify_rfc2231({name, value}) do
    cond do
      match = Regex.run(~r/^(.+)\*(\d+)(\*?)$/, name) ->
        [_, base, section, extended] = match
        {:segment, base, String.to_integer(section), extended == "*", value}

      String.ends_with?(name, "*") ->
        {:segment, String.trim_trailing(name, "*"), 0, true, value}

      true ->
        {:plain, name, value}
    end
  end

  # Assembles segments in order of appearance, keeping the position of the
  # first segment of each parameter. Extended values win over plain ones.
  defp merge_rfc2231([{:plain, name, value} | rest], acc) do
    if List.keymember?(acc, name, 0) do
      merge_rfc2231(rest, acc)
    else
      merge_rfc2231(rest, acc ++ [{name, value}])
    end
  end

  defp merge_rfc2231([{:segment, base, _section, _extended?, _value} = segment | rest], acc) do
    {segments, rest} =
      Enum.split_with(rest, fn
        {:segment, ^base, _n, _e, _v} -> true
        _other -> false
      end)

    value = assemble_segments(Enum.sort_by([segment | segments], &elem(&1, 2)))
    merge_rfc2231(rest, List.keystore(acc, base, 0, {base, value}))
  end

  defp merge_rfc2231([], acc), do: acc

  defp assemble_segments([{:segment, _base, _n, first_extended?, first_value} | _] = segments) do
    {charset, segments} =
      if first_extended? do
        case Regex.run(~r/^([^']*)'[^']*'(.*)$/s, first_value) do
          [_, charset, data] ->
            [{:segment, base, n, extended?, _} | rest] = segments
            {presence(charset), [{:segment, base, n, extended?, data} | rest]}

          nil ->
            {nil, segments}
        end
      else
        {nil, segments}
      end

    bytes =
      segments
      |> Enum.map(fn {:segment, _base, _n, extended?, value} ->
        if extended?, do: percent_decode(value), else: value
      end)
      |> IO.iodata_to_binary()

    if charset, do: Charset.to_utf8(bytes, charset), else: bytes
  end

  defp percent_decode(value), do: percent_decode(value, [])

  defp percent_decode("", acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp percent_decode(<<"%", hi, lo, rest::binary>>, acc) do
    case EmailParser.TransferEncoding.hex_byte(hi, lo) do
      {:ok, byte} -> percent_decode(rest, [<<byte>> | acc])
      :error -> percent_decode(rest, [<<"%", hi, lo>> | acc])
    end
  end

  defp percent_decode(<<char, rest::binary>>, acc), do: percent_decode(rest, [<<char>> | acc])
end
