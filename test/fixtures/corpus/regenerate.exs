# Regenerates the `.expected.exs` golden file next to every `.eml` fixture in
# this directory tree, from the current `EmailParser` output:
#
#     mix run test/fixtures/corpus/regenerate.exs
#
# Each golden records the extraction result with a SHA-256 per attachment
# instead of the raw bytes.
#
# Inspect the diff carefully after regenerating: a changed golden means the
# observable behaviour of `EmailParser` changed.

corpus_dir = Path.dirname(Path.expand(__ENV__.file))

summarize = fn attachments ->
  Enum.map(attachments, fn attachment ->
    %{
      name: attachment.name,
      content_type: attachment.content_type,
      byte_size: byte_size(attachment.content_bytes),
      sha256: Base.encode16(:crypto.hash(:sha256, attachment.content_bytes), case: :lower)
    }
  end)
end

corpus_dir
|> Path.join("*/*.eml")
|> Path.wildcard()
|> Enum.sort()
|> Enum.each(fn eml_path ->
  raw = File.read!(eml_path)

  expected =
    case EmailParser.extract_nested_attachments(raw) do
      {:ok, attachments} -> %{result: :ok, attachments: summarize.(attachments)}
      :error -> %{result: :error, attachments: []}
    end

  golden =
    expected
    |> inspect(limit: :infinity, printable_limit: :infinity)
    |> Code.format_string!()
    |> IO.iodata_to_binary()

  golden_path = String.replace_suffix(eml_path, ".eml", ".expected.exs")
  File.write!(golden_path, golden <> "\n")
end)

count = corpus_dir |> Path.join("*/*.expected.exs") |> Path.wildcard() |> length()
IO.puts("regenerated #{count} golden files under #{Path.relative_to_cwd(corpus_dir)}")
