defmodule EmailParserCorpusTest do
  use ExUnit.Case, async: true

  # Runs `EmailParser` against the vendored message corpus
  # (test/fixtures/corpus) and compares each result with its `.expected.exs`
  # golden file. See test/fixtures/corpus/README.md for provenance and
  # regenerate.exs to rebuild the goldens after an intentional change.

  @corpus_dir Path.expand("fixtures/corpus", __DIR__)

  for eml_path <- @corpus_dir |> Path.join("*/*.eml") |> Path.wildcard() |> Enum.sort() do
    test "extracts the expected attachments from #{Path.relative_to(eml_path, @corpus_dir)}" do
      eml_path = unquote(eml_path)
      golden_path = String.replace_suffix(eml_path, ".eml", ".expected.exs")
      {expected, []} = Code.eval_file(golden_path)

      case EmailParser.extract_nested_attachments(File.read!(eml_path)) do
        :error ->
          assert expected.result == :error

        {:ok, attachments} ->
          assert expected.result == :ok
          assert Enum.map(attachments, &summarize/1) == expected.attachments
      end
    end
  end

  for eml_path <- @corpus_dir |> Path.join("*/*.eml") |> Path.wildcard() |> Enum.sort() do
    test "writes those attachments to disk for #{Path.relative_to(eml_path, @corpus_dir)}" do
      eml_path = unquote(eml_path)
      raw = File.read!(eml_path)
      directory = Path.join(System.tmp_dir!(), "corpus_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(directory) end)

      case EmailParser.extract_nested_attachments(raw) do
        :error ->
          assert :error = EmailParser.extract_attachments_to_disk(raw, directory: directory)

        {:ok, attachments} ->
          assert {:ok, filenames} =
                   EmailParser.extract_attachments_to_disk(raw, directory: directory)

          # One name per attachment, and nothing written outside the directory.
          assert length(filenames) == length(attachments)
          assert Enum.sort(File.ls!(directory)) == filenames |> Enum.uniq() |> Enum.sort()
      end
    end

    test "strips the attachments of #{Path.relative_to(eml_path, @corpus_dir)}" do
      raw = File.read!(unquote(eml_path))

      case EmailParser.extract_nested_attachments(raw) do
        :error ->
          assert :error = EmailParser.strip_attachments(raw)

        {:ok, _attachments} ->
          assert {:ok, %EmailParser.Email{} = email} = EmailParser.strip_attachments(raw)
          assert is_map(email.headers)
          assert email.text_body == nil or String.valid?(email.text_body)
          assert email.html_body == nil or String.valid?(email.html_body)
      end
    end
  end

  defp summarize(attachment) do
    %{
      name: attachment.name,
      content_type: attachment.content_type,
      byte_size: byte_size(attachment.content_bytes),
      sha256: Base.encode16(:crypto.hash(:sha256, attachment.content_bytes), case: :lower)
    }
  end
end
