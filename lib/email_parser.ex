defmodule EmailParser do
  @moduledoc """
  Pure Elixir RFC 5322 / MIME email parser that extracts nested attachments.

  This module exposes the public API; the parsing internals live under
  `lib/email_parser`. The parser is validated against a corpus of real-world
  messages (see `test/fixtures/corpus`).

  Parsing is best-effort and never raises on malformed input:

    * any binary is accepted, valid UTF-8 or not;
    * text parts in UTF-8/ASCII, ISO-8859-1, windows-1252 and UTF-16 are
      converted to UTF-8; text in other charsets is kept with unmappable
      bytes replaced by `U+FFFD`;
    * parts with a broken transfer encoding fall back to their raw bytes, and
      malformed MIME structures are recovered as far as possible.
  """

  alias EmailParser.Attachment
  alias EmailParser.Extractor

  @doc """
  Parses a string containing a RFC5322 raw message and extracts all nested
  attachments.

  A best-effort is made to parse the message and if no headers are found
  `:error` is returned.

  ### Example

      iex> EmailParser.extract_nested_attachments(raw_message)
      {:ok, [%EmailParser.Attachment{name: "example.pdf", content_type: "application/pdf", content_bytes: "..."}]}

  """
  @spec extract_nested_attachments(binary) :: {:ok, [Attachment.t()]} | :error
  def extract_nested_attachments(raw_message) when is_binary(raw_message),
    do: Extractor.extract_nested_attachments(raw_message)
end
