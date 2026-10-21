defmodule EmailParser.Attachment do
  @moduledoc """
  A message attachment.

    * `:name` - the filename the message gives the attachment, decoded to
      UTF-8, or `"untitled"` when the message names none.
    * `:content_type` - the downcased MIME type, such as `"application/pdf"`,
      without parameters; `nil` when the part declares none.
    * `:content_bytes` - the attachment's contents, with the transfer
      encoding undone; `text/*` attachments are also converted to UTF-8.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          content_bytes: binary,
          content_type: String.t() | nil
        }

  defstruct [:name, :content_type, :content_bytes]

  @untitled "untitled"

  @doc false
  # The name given to an attachment the message does not name.
  @spec untitled() :: String.t()
  def untitled, do: @untitled
end
