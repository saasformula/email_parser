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
parseable headers at all.

## What it handles

* multipart trees of any shape (`mixed`, `alternative`, `related`, `digest`,
  `signed`, ...): text parts that render as the message body are not reported
  as attachments, while everything else — inline images included — is;
* base64 and quoted-printable transfer encodings, falling back to the raw
  bytes when a part is incorrectly encoded;
* RFC 2047 encoded words and RFC 2231 extended parameters/continuations in
  attachment names;
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
[test/fixtures/corpus](test/fixtures/corpus).

## License

MIT — see [LICENSE](LICENSE). The vendored test corpus originates from the
mail-parser project by Stalwart Labs (Apache-2.0 OR MIT); see
[test/fixtures/corpus/README.md](test/fixtures/corpus/README.md).
