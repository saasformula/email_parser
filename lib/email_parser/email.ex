defmodule EmailParser.Email do
  @moduledoc """
  A message with its attachments stripped: the header fields plus the bodies.

  `text_body` is always plain text — a message that carries only HTML is
  rendered to text. `html_body` is only set when the message actually carries
  an HTML part.
  """

  alias EmailParser.{EncodedWord, Html, Message, Part}

  @type t :: %__MODULE__{
          headers: %{String.t() => String.t()},
          text_body: String.t() | nil,
          html_body: String.t() | nil
        }

  defstruct headers: %{}, text_body: nil, html_body: nil

  # Headers that describe how the raw body was encoded and presented. The
  # bodies are handed back decoded, so keeping them would misdescribe them.
  @stripped_headers ["content-transfer-encoding", "content-disposition"]

  @doc false
  @spec from_message(Message.t()) :: t
  def from_message(%Message{} = message) do
    %__MODULE__{
      headers: headers(message),
      text_body: body(message, message.text_body, &text_of/1),
      html_body: body(message, message.html_body, &html_of/1)
    }
  end

  defp headers(%Message{} = message) do
    case Message.root_part(message) do
      nil ->
        %{}

      %Part{headers: headers} ->
        headers
        |> Enum.reject(fn {name, _value} -> name in @stripped_headers end)
        |> Enum.reduce(%{}, fn {name, value}, acc ->
          Map.put_new(acc, name, EncodedWord.decode(value))
        end)
    end
  end

  # The first body part of its kind, rendered by `render`.
  defp body(_message, [], _render), do: nil

  defp body(%Message{} = message, [part_id | _rest], render) do
    case Message.part(message, part_id) do
      nil -> nil
      part -> render.(part)
    end
  end

  defp text_of(%Part{body: {:text, text}}), do: text
  defp text_of(%Part{body: {:html, html}}), do: Html.to_text(html)
  defp text_of(%Part{}), do: nil

  defp html_of(%Part{body: {:html, html}}), do: html
  defp html_of(%Part{}), do: nil
end
