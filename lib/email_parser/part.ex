defmodule EmailParser.Part do
  @moduledoc false
  # A single MIME part. `body` is a tagged tuple:
  #
  #   * `{:text, string}` / `{:html, string}` — decoded text content
  #   * `{:binary, bytes}` / `{:inline_binary, bytes}` — decoded binary content
  #   * `{:message, %EmailParser.Message{}}` — a nested message/rfc822
  #   * `{:multipart, [part_id]}` — a multipart container

  alias EmailParser.{ContentType, Header, Message}

  defstruct headers: [],
            content_type: nil,
            content_disposition: nil,
            encoding: :none,
            encoding_problem?: false,
            body: {:text, ""}

  @type body ::
          {:text, String.t()}
          | {:html, String.t()}
          | {:binary, binary}
          | {:inline_binary, binary}
          | {:message, Message.t()}
          | {:multipart, [Message.part_id()]}

  @type t :: %__MODULE__{
          headers: Header.headers(),
          content_type: ContentType.t() | nil,
          content_disposition: ContentType.t() | nil,
          encoding: EmailParser.TransferEncoding.encoding(),
          encoding_problem?: boolean,
          body: body
        }

  @doc "Returns the part's decoded contents as a binary."
  @spec contents(t) :: binary
  def contents(%__MODULE__{body: {tag, text}}) when tag in [:text, :html], do: text
  def contents(%__MODULE__{body: {tag, bytes}}) when tag in [:binary, :inline_binary], do: bytes
  def contents(%__MODULE__{body: {:message, message}}), do: message.raw_message
  def contents(%__MODULE__{body: {:multipart, _ids}}), do: ""

  @doc "Returns the nested message for message/rfc822 parts, or `nil`."
  @spec nested_message(t) :: Message.t() | nil
  def nested_message(%__MODULE__{body: {:message, message}}), do: message
  def nested_message(%__MODULE__{}), do: nil

  @doc """
  Returns the attachment name: the Content-Disposition `filename` parameter,
  falling back to the Content-Type `name` parameter.
  """
  @spec attachment_name(t) :: String.t() | nil
  def attachment_name(%__MODULE__{} = part) do
    ContentType.param(part.content_disposition, "filename") ||
      ContentType.param(part.content_type, "name")
  end

  @doc ~S(Returns the content type formatted as `"type/subtype"` or `"type"`.)
  @spec content_type_string(t) :: String.t() | nil
  def content_type_string(%__MODULE__{content_type: nil}), do: nil

  def content_type_string(%__MODULE__{content_type: content_type}) do
    case content_type.subtype do
      nil -> content_type.type
      subtype -> content_type.type <> "/" <> subtype
    end
  end
end
