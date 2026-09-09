defmodule EmailParser.Disk do
  @moduledoc false
  # Writes extracted attachments to a directory.

  alias EmailParser.Attachment

  @spec write([Attachment.t()], keyword) :: {:ok, [String.t()]} | {:error, File.posix()}
  def write(attachments, opts) do
    directory = Keyword.get(opts, :directory, ".")
    prefix = Keyword.get(opts, :prefix, "")
    mime_types = Keyword.get(opts, :mime_types, [])

    with :ok <- File.mkdir_p(directory) do
      attachments
      |> filter(mime_types)
      |> write_all(directory, prefix, [])
    end
  end

  defp filter(attachments, []), do: attachments

  defp filter(attachments, mime_types),
    do: Enum.filter(attachments, &(&1.content_type in mime_types))

  # A partial write leaves the caller with attachments it cannot account for,
  # so a failure takes the files already written down with it.
  defp write_all([], _directory, _prefix, written), do: {:ok, Enum.reverse(written)}

  defp write_all([attachment | rest], directory, prefix, written) do
    filename = prefix <> safe_name(attachment.name)

    case File.write(Path.join(directory, filename), attachment.content_bytes) do
      :ok ->
        write_all(rest, directory, prefix, [filename | written])

      {:error, reason} ->
        Enum.each(written, &File.rm(Path.join(directory, &1)))
        {:error, reason}
    end
  end

  # Attachment names come from the message, so they may carry path separators
  # or `..` and must not be able to steer the write out of `directory`.
  defp safe_name(name) do
    basename =
      name
      |> String.replace(["\\", "\0"], "/")
      |> Path.basename()
      |> String.trim()

    if basename in ["", ".", ".."], do: Attachment.untitled(), else: basename
  end
end
