defmodule EmailParser.TransferEncoding do
  @moduledoc false
  # Content-Transfer-Encoding handling: base64 and quoted-printable decoding.
  #
  # Any other encoding (7bit, 8bit, binary, unknown tokens) passes the body
  # through untouched. A failed decode returns `:error`
  # so the caller can fall back to the raw bytes.

  alias EmailParser.Header

  @type encoding :: :base64 | :quoted_printable | :none

  @spec encoding_of(Header.headers()) :: encoding
  def encoding_of(headers) do
    case Header.get(headers, "content-transfer-encoding") do
      nil ->
        :none

      value ->
        case value |> String.trim() |> String.downcase(:ascii) do
          "base64" -> :base64
          "quoted-printable" -> :quoted_printable
          _other -> :none
        end
    end
  end

  @spec decode(binary, encoding) :: {:ok, binary} | :error
  def decode(data, :none), do: {:ok, data}

  def decode(data, :base64) do
    cleaned = for <<char <- data>>, char not in [?\s, ?\t, ?\r, ?\n], into: <<>>, do: <<char>>

    case Base.decode64(cleaned) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> Base.decode64(String.trim_trailing(cleaned, "="), padding: false)
    end
  end

  def decode(data, :quoted_printable), do: decode_qp(data, [])

  defp decode_qp("", acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  # CR never reaches the output: the decoder normalizes CRLF to LF, inside
  # escape sequences included.
  defp decode_qp("=\r" <> rest, acc), do: decode_qp("=" <> rest, acc)
  defp decode_qp("\r" <> rest, acc), do: decode_qp(rest, acc)

  # Soft line breaks: `=` at the end of a line is dropped together with the
  # break. At the end of the part the break was consumed by the boundary, so a
  # dangling escape is dropped as well.
  defp decode_qp("=\n" <> rest, acc), do: decode_qp(rest, acc)
  defp decode_qp("=", acc), do: decode_qp("", acc)
  defp decode_qp(<<"=", _single>>, acc), do: decode_qp("", acc)

  defp decode_qp(<<"=", hi, lo, rest::binary>>, acc) do
    case hex_byte(hi, lo) do
      {:ok, byte} -> decode_qp(rest, [<<byte>> | acc])
      :error -> :error
    end
  end

  defp decode_qp(<<char, rest::binary>>, acc), do: decode_qp(rest, [<<char>> | acc])

  @doc false
  @spec hex_byte(byte, byte) :: {:ok, byte} | :error
  def hex_byte(hi, lo) do
    with {:ok, hi} <- hex_digit(hi),
         {:ok, lo} <- hex_digit(lo) do
      {:ok, hi * 16 + lo}
    end
  end

  defp hex_digit(char) when char in ?0..?9, do: {:ok, char - ?0}
  defp hex_digit(char) when char in ?a..?f, do: {:ok, char - ?a + 10}
  defp hex_digit(char) when char in ?A..?F, do: {:ok, char - ?A + 10}
  defp hex_digit(_char), do: :error
end
