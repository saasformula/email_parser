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

  Every function returns `:error` for input that carries no parseable headers
  at all.
  """

  alias EmailParser.Attachment
  alias EmailParser.Disk
  alias EmailParser.Email
  alias EmailParser.Extractor
  alias EmailParser.Parser

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

  @doc """
  Like `extract_nested_attachments/1`, but writes the attachments to disk.

  Returns the names of the files written, in the order the attachments appear
  in the message and including `:prefix`. Attachments sharing a name write to
  the same file.

  ## Options

    * `:directory` - directory to write the attachments to, created when
      missing. Defaults to the current directory (`"."`).
    * `:prefix` - prepended to each filename, to keep attachments of different
      messages apart in a shared directory. Defaults to `""`.
    * `:mime_types` - when given, only attachments whose content type is in
      the list are written. Attachments without a content type are never
      written. Defaults to `[]`, which writes them all.

  Only the last path segment of an attachment's name is used, so a message
  cannot write outside `:directory`. A write failure removes the files already
  written and returns the reason.

  ### Examples

      iex> EmailParser.extract_attachments_to_disk("Subject: no attachments\\r\\n\\r\\nhi", [])
      {:ok, []}

      # EmailParser.extract_attachments_to_disk(raw_message,
      #   directory: "/tmp/inbox",
      #   prefix: "account-",
      #   mime_types: ["application/pdf"])
      # {:ok, ["account-example.pdf"]}

  """
  @spec extract_attachments_to_disk(binary, keyword) ::
          {:ok, [String.t()]} | :error | {:error, File.posix()}
  def extract_attachments_to_disk(raw_message, opts \\ []) when is_binary(raw_message) do
    case extract_nested_attachments(raw_message) do
      {:ok, attachments} -> Disk.write(attachments, opts)
      :error -> :error
    end
  end

  @doc """
  Parses a raw message and returns it without its attachments.

  The returned `EmailParser.Email` carries the message's header fields and its
  bodies. Header names are downcased, since RFC 5322 field names are
  case-insensitive, their values are RFC 2047 decoded, and the first
  occurrence of a repeated field wins. `Content-Transfer-Encoding` and
  `Content-Disposition` are left out: they describe the raw body, and the
  bodies here are decoded.

  ### Example

      iex> {:ok, email} = EmailParser.strip_attachments("From: bob@example.com\\r\\nSubject: Hi\\r\\n\\r\\nHello!")
      iex> email.headers
      %{"from" => "bob@example.com", "subject" => "Hi"}
      iex> email.text_body
      "Hello!"

  """
  @spec strip_attachments(binary) :: {:ok, Email.t()} | :error
  def strip_attachments(raw_message) when is_binary(raw_message) do
    case Parser.parse(raw_message) do
      {:ok, message} -> {:ok, Email.from_message(message)}
      :error -> :error
    end
  end
end
