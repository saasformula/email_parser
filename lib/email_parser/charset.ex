defmodule EmailParser.Charset do
  @moduledoc false
  # Converts text bytes in a declared charset into UTF-8.
  #
  # Supports the charsets that can be handled without external tables
  # (UTF-8/ASCII, ISO-8859-1, windows-1252 and UTF-16); anything else is
  # decoded as UTF-8 with invalid bytes replaced by U+FFFD, matching
  # mail-parser's fallback behaviour for unknown charsets.

  @replacement "�"

  @spec to_utf8(binary, String.t() | nil) :: String.t()
  def to_utf8(bytes, charset \\ nil)

  def to_utf8(bytes, nil), do: utf8_lossy(bytes)

  def to_utf8(bytes, charset) do
    case normalize(charset) do
      :utf8 -> utf8_lossy(bytes)
      :latin1 -> characters_to_utf8(bytes, :latin1)
      :windows1252 -> windows1252_to_utf8(bytes)
      {:utf16, endianness} -> characters_to_utf8(bytes, {:utf16, endianness})
      :unknown -> utf8_lossy(bytes)
    end
  end

  defp normalize(charset) do
    charset =
      charset
      |> String.downcase(:ascii)
      |> String.trim()
      # RFC 2231 allows a language suffix, e.g. "utf-8*en"
      |> String.split("*")
      |> hd()

    case charset do
      c when c in ["utf-8", "utf8", "us-ascii", "ascii", "ansi_x3.4-1968", "csutf8"] ->
        :utf8

      c when c in ["iso-8859-1", "iso8859-1", "iso_8859-1", "latin1", "l1", "cp819", "ibm819"] ->
        :latin1

      c when c in ["windows-1252", "cp1252", "x-cp1252"] ->
        :windows1252

      "utf-16le" ->
        {:utf16, :little}

      "utf-16be" ->
        {:utf16, :big}

      "utf-16" ->
        {:utf16, :big}

      _other ->
        :unknown
    end
  end

  @doc "Decodes `bytes` as UTF-8, replacing invalid byte runs with U+FFFD."
  @spec utf8_lossy(binary) :: String.t()
  def utf8_lossy(bytes) do
    if String.valid?(bytes) do
      bytes
    else
      bytes
      |> String.chunk(:valid)
      |> Enum.map(fn chunk ->
        if String.valid?(chunk), do: chunk, else: String.duplicate(@replacement, byte_size(chunk))
      end)
      |> IO.iodata_to_binary()
    end
  end

  defp characters_to_utf8(bytes, encoding) do
    case :unicode.characters_to_binary(bytes, encoding) do
      utf8 when is_binary(utf8) -> utf8
      {:error, converted, _rest} -> converted <> @replacement
      {:incomplete, converted, _rest} -> converted <> @replacement
    end
  end

  # windows-1252 is ISO-8859-1 with printable characters in the 0x80-0x9F range.
  @windows1252_c1 %{
    0x80 => "€",
    0x82 => "‚",
    0x83 => "ƒ",
    0x84 => "„",
    0x85 => "…",
    0x86 => "†",
    0x87 => "‡",
    0x88 => "ˆ",
    0x89 => "‰",
    0x8A => "Š",
    0x8B => "‹",
    0x8C => "Œ",
    0x8E => "Ž",
    0x91 => "‘",
    0x92 => "’",
    0x93 => "“",
    0x94 => "”",
    0x95 => "•",
    0x96 => "–",
    0x97 => "—",
    0x98 => "˜",
    0x99 => "™",
    0x9A => "š",
    0x9B => "›",
    0x9C => "œ",
    0x9E => "ž",
    0x9F => "Ÿ"
  }

  defp windows1252_to_utf8(bytes) do
    for <<byte <- bytes>>, into: "" do
      cond do
        byte < 0x80 -> <<byte>>
        byte in 0x80..0x9F -> Map.get(@windows1252_c1, byte, @replacement)
        true -> <<byte::utf8>>
      end
    end
  end
end
