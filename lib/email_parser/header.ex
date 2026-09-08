defmodule EmailParser.Header do
  @moduledoc false
  # Splits a raw RFC 5322 message into its header block and body, unfolding
  # folded header lines along the way.
  #
  # Mirrors mail-parser's `parse_headers`: lines without a colon are skipped,
  # a blank (or whitespace-only) line terminates the header block, and hitting
  # the end of input before a blank line leaves the message without a body.

  @type headers :: [{name :: String.t(), value :: String.t()}]

  @doc """
  Splits `raw` into `{headers, body, terminated?}`.

  `headers` is an ordered list of `{downcased_name, unfolded_value}` tuples.
  `terminated?` is `true` when a blank line ended the header block, `false`
  when the input ran out first (message without a body).
  """
  @spec split_block(binary) :: {headers, body :: binary, terminated? :: boolean}
  def split_block(raw) when is_binary(raw), do: collect(raw, [], nil)

  defp collect("", acc, current), do: {finalize(acc, current), "", false}

  defp collect(rest, acc, current) do
    {line, rest} = next_line(rest)

    cond do
      blank?(line) ->
        {finalize(acc, current), rest, true}

      folded_continuation?(line) and current != nil ->
        {name, value} = current
        collect(rest, acc, {name, value <> " " <> String.trim(line)})

      true ->
        case parse_field(line) do
          {:ok, field} -> collect(rest, push(acc, current), field)
          :skip -> collect(rest, push(acc, current), nil)
        end
    end
  end

  defp next_line(bin) do
    case :binary.split(bin, "\n") do
      [line, rest] -> {chomp_cr(line), rest}
      [line] -> {chomp_cr(line), ""}
    end
  end

  defp chomp_cr(line) do
    case line do
      "" -> ""
      _ -> if :binary.last(line) == ?\r, do: binary_part(line, 0, byte_size(line) - 1), else: line
    end
  end

  defp blank?(line), do: String.trim(line) == ""

  defp folded_continuation?(<<ws, _::binary>>) when ws in [?\s, ?\t], do: true
  defp folded_continuation?(_line), do: false

  defp parse_field(line) do
    case :binary.split(line, ":") do
      [name, value] ->
        case String.trim(name) do
          "" -> :skip
          name -> {:ok, {String.downcase(name, :ascii), String.trim(value)}}
        end

      _no_colon ->
        :skip
    end
  end

  defp push(acc, nil), do: acc
  defp push(acc, field), do: [field | acc]

  defp finalize(acc, current), do: Enum.reverse(push(acc, current))

  @doc "Returns the value of the first header named `name`, or `nil`."
  @spec get(headers, String.t()) :: String.t() | nil
  def get(headers, name) do
    Enum.find_value(headers, fn
      {^name, value} -> value
      _other -> nil
    end)
  end
end
