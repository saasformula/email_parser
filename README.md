# EmailParser

Pure Elixir RFC 5322 / MIME email parser that extracts nested attachments.
No native code, no dependencies.

```elixir
{:ok, attachments} = EmailParser.extract_nested_attachments(raw_message)

[
  %EmailParser.Attachment{
    name: "example.pdf",
    content_type: "application/pdf",
    content_bytes: <<...>>
  }
] = attachments
```

`extract_nested_attachments/1` parses a raw message on a best-effort basis and
returns every attachment, recursing into nested `message/rfc822` parts
(forwarded messages). It returns `:error` only when the input contains no
parseable headers at all, as every function here does.

## Writing the attachments out

`extract_attachments_to_disk/2` writes them instead of returning their bytes,
and answers with the names of the files it wrote:

```elixir
{:ok, ["msg7-example.pdf"]} =
  EmailParser.extract_attachments_to_disk(raw_message,
    directory: "/tmp/inbox",
    prefix: "msg7-",
    mime_types: ["application/pdf"]
  )
```

The directory is created when missing and defaults to the current one; the
prefix keeps attachments of different messages apart in a shared directory;
`:mime_types` restricts what is written, and defaults to everything. Only the
last path segment of an attachment's name is used, so a message cannot write
outside the directory, and a failed write takes the files already written down
with it.

## Reading the message itself

`strip_attachments/1` answers with the message minus its attachments — the
header fields and the bodies:

```elixir
{:ok, email} = EmailParser.strip_attachments(raw_message)

%EmailParser.Email{
  headers: %{"from" => "bob@example.com", "subject" => "Orçamento"},
  text_body: "Segue o orçamento.",
  html_body: "<p>Segue o orçamento.</p>"
} = email
```

Header names are downcased, since RFC 5322 field names are case-insensitive,
their values are RFC 2047 decoded, and the first occurrence of a repeated
field wins. `Content-Transfer-Encoding` and `Content-Disposition` are left
out: they describe the raw body, and the bodies here are decoded.

`text_body` is always plain text — a message carrying only HTML is rendered to
text, with markup dropped, block elements broken onto their own line and
character references resolved. `html_body` is set only when the message
actually carries an HTML part.

## What it handles

* multipart trees of any shape (`mixed`, `alternative`, `related`, `digest`,
  `signed`, ...): text parts that render as the message body are not reported
  as attachments, while everything else — inline images included — is;
* base64 and quoted-printable transfer encodings, falling back to the raw
  bytes when a part is incorrectly encoded;
* RFC 2047 encoded words and RFC 2231 extended parameters/continuations in
  attachment names, and the raw 8-bit bytes non-conforming mailers write
  there, read as UTF-8 when they form valid UTF-8 and as ISO-8859-1 otherwise;
* charset conversion to UTF-8 for UTF-8/ASCII, ISO-8859-1, windows-1252 and
  UTF-16 text (other charsets are kept with unmappable bytes replaced by
  `U+FFFD`);
* nested `message/rfc822` attachments, unencoded or encoded, with encoded
  nesting limited to 3 levels;
* any binary as input — invalid UTF-8 and malformed MIME structures are
  handled without raising.

## Testing

Besides its unit suite, the parser runs against a vendored corpus of 95
real-world messages — RFC samples, output of historical mail clients,
charset-heavy messages and deliberately malformed ones — each with a golden
file describing the expected attachments. See
[test/fixtures/corpus](test/fixtures/corpus). Every corpus message is also run
through `extract_attachments_to_disk/2` and `strip_attachments/1`.

## License

MIT — see [LICENSE](LICENSE). The vendored test corpus originates from the
mail-parser project by Stalwart Labs (Apache-2.0 OR MIT); see
[test/fixtures/corpus/README.md](test/fixtures/corpus/README.md).
