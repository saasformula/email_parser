defmodule EmailParser do
  @moduledoc """
  Pure Elixir RFC 5322 / MIME email parser that extracts nested attachments.

  The parsing behaviour mirrors the [mail-parser](https://github.com/stalwartlabs/mail-parser)
  Rust crate (version 0.8.2) as wrapped by the
  [mail_parser](https://github.com/kloeckner-i/mail_parser) NIF library, and
  is validated against that crate's own test corpus (see
  `test/fixtures/corpus`). This module exposes the public API; the parsing
  internals live under `lib/email_parser`.

  Known differences from the NIF-based `MailParser`:

    * any binary is accepted, whereas the NIF raises `ArgumentError` on
      input that is not valid UTF-8;
    * fewer legacy charsets are converted to UTF-8 (UTF-8/ASCII, ISO-8859-1,
      windows-1252 and UTF-16; the NIF also handles the remaining ISO-8859-x,
      windows-125x, KOI8 and UTF-7 families). Text in an unsupported charset
      is kept with unmappable bytes replaced by `U+FFFD`;
    * messages with a malformed MIME structure are recovered on a best-effort
      basis in both implementations, but the fallback parts they produce may
      differ.
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
