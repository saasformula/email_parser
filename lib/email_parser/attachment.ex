defmodule EmailParser.Attachment do
  @moduledoc """
  A message attachment.
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
