defmodule EmailParserTest do
  use ExUnit.Case, async: true

  doctest EmailParser, except: [extract_nested_attachments: 1]

  alias EmailParser.Attachment
  alias EmailParser.Email

  describe "attachment extraction from a real-world message" do
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

    test "normalizes CRLF to LF in quoted-printable parts" do
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

  describe "strip_attachments/1" do
    test "returns the header fields with downcased names" do
      raw = """
      Return-Path: <bounce@example.com>
      From: Bob <bob@example.com>
      TO: alice@example.com
      Subject: Quarterly report

      body
      """

      assert {:ok, %Email{headers: headers}} = EmailParser.strip_attachments(raw)

      assert headers == %{
               "return-path" => "<bounce@example.com>",
               "from" => "Bob <bob@example.com>",
               "to" => "alice@example.com",
               "subject" => "Quarterly report"
             }
    end

    test "decodes RFC 2047 encoded words in header values" do
      raw = """
      From: a@example.com
      Subject: =?utf-8?B?T3LDp2FtZW50bw==?= =?utf-8?q?_aprovado?=

      body
      """

      assert {:ok, %Email{headers: %{"subject" => "Orçamento aprovado"}}} =
               EmailParser.strip_attachments(raw)
    end

    test "keeps the first occurrence of a repeated field" do
      raw = """
      Received: from second.example.com
      Received: from first.example.com

      body
      """

      assert {:ok, %Email{headers: %{"received" => "from second.example.com"}}} =
               EmailParser.strip_attachments(raw)
    end

    test "leaves out the headers describing the raw body" do
      raw = """
      From: a@example.com
      Content-Type: text/plain
      Content-Transfer-Encoding: base64
      Content-Disposition: inline

      Ym9keQ==
      """

      assert {:ok, %Email{headers: headers, text_body: "body"}} =
               EmailParser.strip_attachments(raw)

      assert Map.keys(headers) |> Enum.sort() == ["content-type", "from"]
    end

    test "returns the plain text and html bodies of an alternative message" do
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

      assert {:ok, %Email{text_body: "plain body", html_body: "<p>html body</p>"}} =
               EmailParser.strip_attachments(raw)
    end

    test "renders an html-only message as text" do
      raw = """
      From: a@example.com
      Content-Type: text/html; charset="utf-8"

      <html><head><style>p { color: red }</style></head>
      <body><p>Hello   <b>Bob</b>,</p><p>see&nbsp;you&#33;</p></body></html>
      """

      assert {:ok, %Email{text_body: "Hello Bob,\n\nsee you!", html_body: html}} =
               EmailParser.strip_attachments(raw)

      assert html =~ "<p>Hello"
    end

    test "renders line breaks, scripts and character references" do
      raw = """
      From: a@example.com
      Content-Type: text/html

      <div>one<br>two<script>alert("x")</script></div>
      <!-- a comment -->
      <p>caf&eacute; &amp; 5 &lt; 6 &#x2014; ok</p>
      """

      assert {:ok, %Email{text_body: text}} = EmailParser.strip_attachments(raw)
      assert text == "one\ntwo\n\ncafé & 5 < 6 — ok"
    end

    test "leaves html_body unset when the message carries no html" do
      assert {:ok, %Email{text_body: "just text", html_body: nil}} =
               EmailParser.strip_attachments("From: a@example.com\n\njust text")
    end

    test "does not report an attachment as a body" do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: text/plain

      the body
      --mix
      Content-Type: application/pdf
      Content-Disposition: attachment; filename="report.pdf"
      Content-Transfer-Encoding: base64

      JVBERi0=
      --mix--
      """

      assert {:ok, %Email{text_body: "the body", html_body: nil}} =
               EmailParser.strip_attachments(raw)
    end

    test "decodes the body charset and transfer encoding" do
      raw = """
      From: a@example.com
      Content-Type: text/plain; charset="iso-8859-1"
      Content-Transfer-Encoding: quoted-printable

      Kl=F6ckner
      """

      assert {:ok, %Email{text_body: "Klöckner\n"}} = EmailParser.strip_attachments(raw)
    end

    test "returns error when the input has no headers at all" do
      assert :error = EmailParser.strip_attachments("")
      assert :error = EmailParser.strip_attachments("this is not a message")
    end
  end

  describe "extract_attachments_to_disk/2" do
    setup do
      directory =
        Path.join(System.tmp_dir!(), "email_parser_test_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(directory) end)
      {:ok, directory: directory}
    end

    test "writes every attachment and creates the directory", %{directory: directory} do
      assert {:ok, ["notes.txt", "report.pdf"]} =
               EmailParser.extract_attachments_to_disk(two_attachments(), directory: directory)

      assert File.read!(Path.join(directory, "notes.txt")) == "attached notes"
      assert File.read!(Path.join(directory, "report.pdf")) == "%PDF-"
    end

    test "prepends the prefix to every filename", %{directory: directory} do
      assert {:ok, ["ev1-notes.txt", "ev1-report.pdf"]} =
               EmailParser.extract_attachments_to_disk(two_attachments(),
                 directory: directory,
                 prefix: "ev1-"
               )

      assert File.exists?(Path.join(directory, "ev1-report.pdf"))
    end

    test "writes only the requested mime types", %{directory: directory} do
      assert {:ok, ["report.pdf"]} =
               EmailParser.extract_attachments_to_disk(two_attachments(),
                 directory: directory,
                 mime_types: ["application/pdf"]
               )

      assert File.ls!(directory) == ["report.pdf"]
    end

    test "skips attachments without a content type when filtering", %{directory: directory} do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: text/plain

      body
      --mix
      Content-Disposition: attachment; filename="mystery.bin"

      no content type here
      --mix--
      """

      assert {:ok, []} =
               EmailParser.extract_attachments_to_disk(raw,
                 directory: directory,
                 mime_types: ["application/pdf"]
               )

      assert {:ok, ["mystery.bin"]} =
               EmailParser.extract_attachments_to_disk(raw, directory: directory)
    end

    test "confines a traversing attachment name to the directory", %{directory: directory} do
      raw = """
      From: a@example.com
      Content-Type: multipart/mixed; boundary="mix"

      --mix
      Content-Type: text/plain

      body
      --mix
      Content-Type: application/pdf
      Content-Disposition: attachment; filename="../../escaped.pdf"

      pwned
      --mix--
      """

      assert {:ok, ["escaped.pdf"]} =
               EmailParser.extract_attachments_to_disk(raw, directory: directory)

      assert File.read!(Path.join(directory, "escaped.pdf")) == "pwned"
    end

    test "returns an empty list for a message without attachments", %{directory: directory} do
      assert {:ok, []} =
               EmailParser.extract_attachments_to_disk("From: a@example.com\n\nhi",
                 directory: directory
               )
    end

    test "returns the reason when the directory cannot be created" do
      file =
        Path.join(
          System.tmp_dir!(),
          "email_parser_test_file_#{System.unique_integer([:positive])}"
        )

      File.write!(file, "")
      on_exit(fn -> File.rm(file) end)

      assert {:error, :enotdir} =
               EmailParser.extract_attachments_to_disk(two_attachments(),
                 directory: Path.join(file, "nested")
               )
    end

    test "removes what it already wrote when a write fails", %{directory: directory} do
      # The second attachment cannot be written over a directory of that name.
      File.mkdir_p!(Path.join(directory, "report.pdf"))

      assert {:error, :eisdir} =
               EmailParser.extract_attachments_to_disk(two_attachments(), directory: directory)

      refute File.exists?(Path.join(directory, "notes.txt"))
    end

    test "returns error when the input has no headers at all", %{directory: directory} do
      assert :error = EmailParser.extract_attachments_to_disk("nope", directory: directory)
    end
  end

  defp two_attachments do
    """
    From: a@example.com
    Content-Type: multipart/mixed; boundary="mix"

    --mix
    Content-Type: text/plain

    body
    --mix
    Content-Type: text/plain; charset="utf-8"
    Content-Disposition: attachment; filename="notes.txt"

    attached notes
    --mix
    Content-Type: application/pdf
    Content-Disposition: attachment; filename="report.pdf"

    %PDF-
    --mix--
    """
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
