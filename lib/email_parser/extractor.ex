defmodule EmailParser.Extractor do
  @moduledoc false
  # Walks a parsed message and collects its attachments, recursing into
  # nested message/rfc822 parts, mirroring the mail-parser crate's
  # attachment iteration.

  alias EmailParser.Attachment
  alias EmailParser.{Message, Parser, Part}

  @untitled "untitled"

  @spec extract_nested_attachments(binary) :: {:ok, [Attachment.t()]} | :error
  def extract_nested_attachments(raw_message) when is_binary(raw_message) do
    case Parser.parse(raw_message) do
      {:ok, message} -> {:ok, collect(message)}
      :error -> :error
    end
  end

  defp collect(%Message{} = message) do
    Enum.flat_map(message.attachments, fn part_id ->
      part = Message.part(message, part_id)

      case Part.nested_message(part) do
        nil -> [to_attachment(part)]
        nested -> collect(nested)
      end
    end)
  end

  defp to_attachment(%Part{} = part) do
    %Attachment{
      name: Part.attachment_name(part) || @untitled,
      content_type: Part.content_type_string(part),
      content_bytes: Part.contents(part)
    }
  end
end
