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

  defp summarize(attachment) do
    %{
      name: attachment.name,
      content_type: attachment.content_type,
      byte_size: byte_size(attachment.content_bytes),
      sha256: Base.encode16(:crypto.hash(:sha256, attachment.content_bytes), case: :lower)
    }
  end
end
