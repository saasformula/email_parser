# EmailParser

Pure Elixir RFC 5322 / MIME email parser that extracts nested attachments.
No NIFs, no dependencies.

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
  `signed`, ...), with the body/attachment classification of the
  [mail-parser](https://github.com/stalwartlabs/mail-parser) Rust crate:
  text parts that render as the message body are not reported as attachments,
  while everything else — inline images included — is;
* base64 and quoted-printable transfer encodings, falling back to the raw
  bytes when a part is incorrectly encoded;
* RFC 2047 encoded words and RFC 2231 extended parameters/continuations in
  attachment names;
* charset conversion to UTF-8 for UTF-8/ASCII, ISO-8859-1, windows-1252 and
  UTF-16 text (other charsets are kept with unmappable bytes replaced by
  `U+FFFD`);
* nested `message/rfc822` attachments, unencoded or encoded, with encoded
  nesting limited to 3 levels.

## Compatibility and testing

The behaviour intentionally mirrors the mail-parser Rust crate (0.8.2) as
wrapped by the [mail_parser](https://github.com/kloeckner-i/mail_parser) NIF
library, so this package can serve as a drop-in, NIF-free replacement. It is
tested against the crate's own 95-message corpus (vendored under
[test/fixtures/corpus](test/fixtures/corpus)): every well-formed message the
NIF can parse produces byte-identical attachments, and the known differences
(non-UTF-8 input, charset breadth, malformed-MIME recovery) are documented in
the `EmailParser` moduledoc and recorded per fixture in the corpus goldens.

## License

MIT — see [LICENSE](LICENSE). The vendored test corpus originates from the
mail-parser project by Stalwart Labs (Apache-2.0 OR MIT); see
[test/fixtures/corpus/README.md](test/fixtures/corpus/README.md).
