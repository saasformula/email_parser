defmodule EmailParserTest do
  use ExUnit.Case, async: true

  doctest EmailParser, except: [extract_nested_attachments: 1]

  alias EmailParser.Attachment

  describe "parity with the mail_parser NIF suite" do
    test "extracts attachments from raw message" do
      raw_message = File.read!("test/fixtures/example.txt")

      assert {:ok,
              [
                %Attachment{
                  name: "Best 340 Klöckner FL-Stahl.pdf",
                  content_type: "application/pdf",
                  content_bytes: pdf_content_bytes
                },
                %Attachment{
                  name: "smime.p7s",
                  content_type: "application/x-pkcs7-signature",
                  content_bytes: "redacted"
                }
              ]} = EmailParser.extract_nested_attachments(raw_message)

      assert pdf_content_bytes == File.read!("test/fixtures/sample.pdf")
    end

    test "returns error if parsing fails" do
      assert :error = EmailParser.extract_nested_attachments("")
    end
  end

  describe "error handling" do
    test "returns error when the input has no headers at all" do
      assert :error = EmailParser.extract_nested_attachments("this is not a message")
      assert :error = EmailParser.extract_nested_attachments("no colon here\nnor here\n")
    end

    test "accepts a message that starts at the body" do
      assert {:ok, []} = EmailParser.extract_nested_attachments("\nHello!")
    end

    test "accepts a message without a body" do
      assert {:ok, []} = EmailParser.extract_nested_attachments("Subject: no body")
    end
  end

  describe "bodies vs attachments" do
    test "text and html alternative parts are not attachments" do
      raw = """
      From: a@example.com
      Content-Type: multipart/alternative; boundary="alt"

      --alt
      Content-Type: text/plain

      plain body
      --alt
      Content-Type: text/html

      <p>html body</p>
      --alt--
      """

      assert {:ok, []} = EmailParser.extract_nested_attachments(raw)
    end

    test "a text part with an attachment disposition is extracted" do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: text/plain

      body
      --mix
      Content-Type: text/plain; charset="utf-8"
      Content-Disposition: attachment; filename="notes.txt"

      attached notes
      --mix--
      """

      assert {:ok,
              [
                %Attachment{
                  name: "notes.txt",
                  content_type: "text/plain",
                  content_bytes: "attached notes"
                }
              ]} = EmailParser.extract_nested_attachments(raw)
    end

    test "an inline image without a disposition is extracted" do
      png = <<137, "PNG", 13, 10, 26, 10, 0, 1, 2, 3>>

      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: text/plain

      body
      --mix
      Content-Type: image/png

      #{Base.encode64(png)}
      --mix--
      """

      # The image is not base64 encoded (no Content-Transfer-Encoding), so its
      # bytes are the literal body; what matters is that it is extracted.
      assert {:ok, [%Attachment{name: "untitled", content_type: "image/png"}]} =
               EmailParser.extract_nested_attachments(raw)
    end
  end

  describe "attachment naming" do
    test "falls back to the Content-Type name parameter" do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: application/octet-stream; name="data.bin"
      Content-Transfer-Encoding: base64

      #{Base.encode64("payload")}
      --mix--
      """

      assert {:ok, [%Attachment{name: "data.bin", content_bytes: "payload"}]} =
               EmailParser.extract_nested_attachments(raw)
    end

    test "uses untitled when no name is present" do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: application/octet-stream
      Content-Transfer-Encoding: base64

      #{Base.encode64("payload")}
      --mix--
      """

      assert {:ok, [%Attachment{name: "untitled", content_type: "application/octet-stream"}]} =
               EmailParser.extract_nested_attachments(raw)
    end

    test "decodes RFC 2047 base64 encoded filenames" do
      encoded_name = "=?utf-8?B?#{Base.encode64("relatório final.pdf")}?="

      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: application/pdf
      Content-Disposition: attachment; filename="#{encoded_name}"
      Content-Transfer-Encoding: base64

      #{Base.encode64("pdf bytes")}
      --mix--
      """

      assert {:ok, [%Attachment{name: "relatório final.pdf"}]} =
               EmailParser.extract_nested_attachments(raw)
    end

    test "decodes adjacent RFC 2047 quoted-printable encoded words" do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: application/pdf
      Content-Disposition: attachment;
      \tfilename="=?iso-8859-1?Q?Kl=F6ckner?= =?iso-8859-1?Q?_Stahl.pdf?="
      Content-Transfer-Encoding: base64

      #{Base.encode64("pdf bytes")}
      --mix--
      """

      assert {:ok, [%Attachment{name: "Klöckner Stahl.pdf"}]} =
               EmailParser.extract_nested_attachments(raw)
    end

    test "decodes RFC 2231 extended parameter continuations" do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: application/pdf
      Content-Disposition: attachment;
      \tfilename*0*=utf-8''relat%C3%B3rio%20;
      \tfilename*1=final.pdf
      Content-Transfer-Encoding: base64

      #{Base.encode64("pdf bytes")}
      --mix--
      """

      assert {:ok, [%Attachment{name: "relatório final.pdf"}]} =
               EmailParser.extract_nested_attachments(raw)
    end
  end

  describe "content decoding" do
    test "decodes base64 bodies ignoring line breaks" do
      bytes = :crypto.strong_rand_bytes(600)

      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: application/octet-stream; name="blob.bin"
      Content-Transfer-Encoding: base64

      #{Base.encode64(bytes) |> chunk_lines()}
      --mix--
      """

      assert {:ok, [%Attachment{name: "blob.bin", content_bytes: ^bytes}]} =
               EmailParser.extract_nested_attachments(raw)
    end

    test "decodes quoted-printable text attachments with charset conversion" do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: text/plain; charset="iso-8859-1"
      Content-Disposition: attachment; filename="gruss.txt"
      Content-Transfer-Encoding: quoted-printable

      Mit freundlichen Gr=FC=DFen und einem sehr langen Satz, der hier weiterge=
      hen soll.
      --mix--
      """

      assert {:ok, [%Attachment{name: "gruss.txt", content_bytes: text}]} =
               EmailParser.extract_nested_attachments(raw)

      assert text ==
               "Mit freundlichen Grüßen und einem sehr langen Satz, der hier weitergehen soll."
    end

    test "normalizes CRLF to LF in quoted-printable parts, like the mail-parser crate" do
      raw =
        """
        From: a@example.com
        Content-Type: multipart/mixed; boundary="mix"

        --mix
        Content-Type: text/plain; charset="iso-8859-1"
        Content-Disposition: attachment; filename="fabel.txt"
        Content-Transfer-Encoding: quoted-printable

        Die Hasen und die Fr=F6sche
        klagten einst =FCber ihre Lage; sie wollten ein f=FCr allemal sterben.=
        ..
        --mix--
        """
        |> String.replace("\n", "\r\n")

      assert {:ok, [%Attachment{name: "fabel.txt", content_bytes: text}]} =
               EmailParser.extract_nested_attachments(raw)

      assert text ==
               "Die Hasen und die Frösche\n" <>
                 "klagten einst über ihre Lage; sie wollten ein für allemal sterben..."
    end

    test "falls back to the raw bytes when the transfer encoding is invalid" do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: application/octet-stream; name="broken.bin"
      Content-Transfer-Encoding: base64

      this is *not* valid base64!
      --mix--
      """

      assert {:ok,
              [%Attachment{name: "broken.bin", content_bytes: "this is *not* valid base64!"}]} =
               EmailParser.extract_nested_attachments(raw)
    end
  end

  describe "nested messages" do
    test "flattens attachments of an unencoded message/rfc822 part" do
      inner = """
      From: inner@example.com
      Content-Type: multipart/mixed; boundary="inner"

      --inner
      Content-Type: text/plain

      inner body
      --inner
      Content-Type: application/pdf; name="inner.pdf"
      Content-Transfer-Encoding: base64

      #{Base.encode64("inner pdf")}
      --inner--
      """

      raw = """
      From: outer@example.com
      Content-Type: multipart/mixed; boundary="outer"

      --outer
      Content-Type: text/plain

      outer body
      --outer
      Content-Type: message/rfc822

      #{inner}
      --outer--
      """

      assert {:ok, [%Attachment{name: "inner.pdf", content_bytes: "inner pdf"}]} =
               EmailParser.extract_nested_attachments(raw)
    end

    test "flattens attachments of a base64 encoded message/rfc822 part" do
      inner = """
      From: inner@example.com
      Content-Type: multipart/mixed; boundary="inner"

      --inner
      Content-Type: application/pdf
      Content-Disposition: attachment; filename="report.pdf"
      Content-Transfer-Encoding: base64

      #{Base.encode64("report")}
      --inner--
      """

      raw = """
      From: outer@example.com
      Content-Type: multipart/mixed; boundary="outer"

      --outer
      Content-Type: message/rfc822; name="forwarded.eml"
      Content-Transfer-Encoding: base64

      #{inner |> Base.encode64() |> chunk_lines()}
      --outer--
      """

      assert {:ok, [%Attachment{name: "report.pdf", content_bytes: "report"}]} =
               EmailParser.extract_nested_attachments(raw)
    end

    test "stops recursing into encoded messages after three levels" do
      innermost = """
      From: deep@example.com
      Content-Type: multipart/mixed; boundary="deep"

      --deep
      Content-Type: application/pdf; name="deep.pdf"
      Content-Transfer-Encoding: base64

      #{Base.encode64("deep pdf")}
      --deep--
      """

      raw = Enum.reduce(1..4, innermost, &wrap_in_encoded_message/2)

      assert {:ok, [%Attachment{name: "untitled", content_type: "message/rfc822"}]} =
               EmailParser.extract_nested_attachments(raw)
    end
  end

  defp wrap_in_encoded_message(level, inner) do
    """
    From: level#{level}@example.com
    Content-Type: multipart/mixed; boundary="wrap#{level}"

    --wrap#{level}
    Content-Type: message/rfc822
    Content-Transfer-Encoding: base64

    #{inner |> Base.encode64() |> chunk_lines()}
    --wrap#{level}--
    """
  end

  defp chunk_lines(encoded) do
    encoded
    |> Stream.unfold(fn
      "" -> nil
      rest -> String.split_at(rest, 76)
    end)
    |> Enum.join("\n")
  end
end
