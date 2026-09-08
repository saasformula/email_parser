defmodule EmailParser.EncodedWord do
  @moduledoc false
  # RFC 2047 encoded-word decoding for header values, e.g.
  # `=?iso-8859-1?Q?Kl=F6ckner?=` -> "Klöckner".
  #
  # Invalid encoded words are left as literal text, and whitespace between two
  # adjacent encoded words is dropped (RFC 2047, section 6.2).

  alias EmailParser.Charset

  @spec decode(String.t()) :: String.t()
  def decode(string) when is_binary(string) do
    string
    |> tokenize([])
    |> merge_words([])
    |> IO.iodata_to_binary()
  end

  defp tokenize(rest, acc) do
    case :binary.split(rest, "=?") do
      [text] ->
        Enum.reverse(push_text(acc, text))

      [text, candidate] ->
        case parse_word(candidate) do
          {:ok, decoded, remainder} ->
            tokenize(remainder, [{:word, decoded} | push_text(acc, text)])

          :error ->
            tokenize(candidate, push_text(acc, text <> "=?"))
        end
    end
  end

  defp push_text(acc, ""), do: acc
  defp push_text(acc, text), do: [{:text, text} | acc]

  # Parses `charset?encoding?data?=` (the part following "=?").
  defp parse_word(rest) do
    with [charset, rest] when charset != "" <- :binary.split(rest, "?"),
         <<encoding, "?", rest::binary>> <- rest,
         [data, remainder] <- :binary.split(rest, "?="),
         {:ok, bytes} <- decode_data(encoding, data) do
      {:ok, Charset.to_utf8(bytes, charset), remainder}
    else
      _invalid -> :error
    end
  end

  defp decode_data(encoding, data) when encoding in [?B, ?b] do
    case Base.decode64(data) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> Base.decode64(String.trim_trailing(data, "="), padding: false)
    end
  end

  defp decode_data(encoding, data) when encoding in [?Q, ?q], do: decode_q(data, [])

  defp decode_data(_encoding, _data), do: :error

  defp decode_q("", acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
  defp decode_q("_" <> rest, acc), do: decode_q(rest, [" " | acc])

  defp decode_q(<<"=", hi, lo, rest::binary>>, acc) do
    case EmailParser.TransferEncoding.hex_byte(hi, lo) do
      {:ok, byte} -> decode_q(rest, [<<byte>> | acc])
      :error -> :error
    end
  end

  defp decode_q("=" <> _rest, _acc), do: :error
  defp decode_q(<<char, rest::binary>>, acc), do: decode_q(rest, [<<char>> | acc])

  # Drops whitespace-only text between two decoded words.
  defp merge_words([{:word, word}, {:text, text} | rest], acc) do
    if String.trim(text) == "" and match?([{:word, _} | _], rest) do
      merge_words(rest, [word | acc])
    else
      merge_words(rest, [text, word | acc])
    end
  end

  defp merge_words([{:word, word} | rest], acc), do: merge_words(rest, [word | acc])
  defp merge_words([{:text, text} | rest], acc), do: merge_words(rest, [text | acc])
  defp merge_words([], acc), do: Enum.reverse(acc)
end
