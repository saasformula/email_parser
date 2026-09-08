defmodule EmailParser.Message do
  @moduledoc false
  # A parsed message: an ordered list of MIME parts plus the part ids that
  # make up the text body, the HTML body and the attachments — the same
  # shape as mail-parser's `Message` struct.

  alias EmailParser.Part

  defstruct raw_message: "", parts: [], text_body: [], html_body: [], attachments: []

  @type part_id :: non_neg_integer
  @type t :: %__MODULE__{
          raw_message: binary,
          parts: [Part.t()],
          text_body: [part_id],
          html_body: [part_id],
          attachments: [part_id]
        }

  @spec part(t, part_id) :: Part.t() | nil
  def part(%__MODULE__{parts: parts}, id), do: Enum.at(parts, id)

  @doc false
  @spec add_part(t, Part.t()) :: t
  def add_part(%__MODULE__{} = message, %Part{} = part),
    do: %{message | parts: message.parts ++ [part]}

  @doc false
  @spec update_part(t, part_id, (Part.t() -> Part.t())) :: t
  def update_part(%__MODULE__{} = message, id, fun),
    do: %{message | parts: List.update_at(message.parts, id, fun)}
end
