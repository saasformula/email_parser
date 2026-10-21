# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

First public release.

### Added

- `EmailParser.extract_nested_attachments/1`, returning every attachment of a
  raw RFC 5322 message, recursing into nested `message/rfc822` parts.
- `EmailParser.extract_attachments_to_disk/2`, writing those attachments to a
  directory, with `:directory`, `:prefix` and `:mime_types` options.
- `EmailParser.strip_attachments/1`, returning the message's decoded header
  fields and its text and HTML bodies as an `EmailParser.Email`.

[0.1.0]: https://github.com/saasformula/email_parser/releases/tag/v0.1.0
