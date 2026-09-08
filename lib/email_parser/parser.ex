defmodule EmailParser.Parser do
  @moduledoc false
  # Parses a raw RFC 5322 message into a `EmailParser.Message` tree.
  #
  # The part classification (which parts become the text body, the HTML body
  # or attachments) follows these rules:
  #
  #   * text parts are body candidates while they look inline (no attachment
  #     disposition, no `name` parameter outside the first part);
  #   * every other leaf part — including inline images and parts that fail
  #     to decode — is an attachment;
  #   * message/rfc822 parts are parsed recursively, with encoded nesting
  #     limited to 3 levels.

  alias EmailParser.{Charset, ContentType, Header, Message, Part, TransferEncoding}

  @max_nested_encoded 3

  defmodule State do
    @moduledoc false
    # Per-container parser state.
    defstruct mime: :message,
              in_alternative: false,
              parts: 0,
              html_parts: 0,
              text_parts: 0,
              need_html: true,
              need_text: true
  end

  @spec parse(binary) :: {:ok, Message.t()} | :error
  def parse(raw_message) when is_binary(raw_message),
    do: parse_message(raw_message, @max_nested_encoded)

  defp parse_message(raw, depth) do
    case Header.split_block(raw) do
      {[], _body, false} ->
        :error

      {headers, body, _terminated?} ->
        {message, _state} =
          process_entity(%Message{raw_message: raw}, %State{}, headers, body, depth)

        {:ok, message}
    end
  end

  defp process_entity(message, state, headers, body, depth) do
    state = %{state | parts: state.parts + 1}
    content_type = find_structured(headers, "content-type")
    disposition = find_structured(headers, "content-disposition")
    {multipart?, inline?, text?, class} = mime_class(content_type, state.mime)

    boundary = ContentType.param(content_type, "boundary")

    if multipart? and boundary not in [nil, ""] do
      case split_multipart(body, boundary) do
        {:ok, chunks} ->
          process_multipart(
            message,
            state,
            headers,
            content_type,
            disposition,
            class,
            chunks,
            depth
          )

        :not_found ->
          # No boundary in the body: recover the whole body as plain text.
          flags = {false, true, :text_other}
          process_leaf(message, state, headers, content_type, disposition, flags, body, depth)
      end
    else
      # Note: a multipart content type without a boundary parameter falls
      # through as an ordinary (binary) leaf part.
      flags = {inline?, text?, class}
      process_leaf(message, state, headers, content_type, disposition, flags, body, depth)
    end
  end

  ## Multipart containers

  defp process_multipart(message, state, headers, content_type, disposition, class, chunks, depth) do
    container_id = length(message.parts)

    message =
      Message.add_part(message, %Part{
        headers: headers,
        content_type: content_type,
        content_disposition: disposition,
        body: {:multipart, []}
      })

    child_state = %State{
      mime: class,
      in_alternative: state.in_alternative or class == :multipart_alternative,
      html_parts: length(message.html_body),
      text_parts: length(message.text_body),
      need_html: state.need_html,
      need_text: state.need_text
    }

    {message, child_state, sub_ids} =
      Enum.reduce(chunks, {message, child_state, []}, fn chunk, {message, child_state, ids} ->
        ids = ids ++ [length(message.parts)]
        {headers, body, _terminated?} = Header.split_block(chunk)
        {message, child_state} = process_entity(message, child_state, headers, body, depth)
        {message, child_state, ids}
      end)

    message
    |> fixup_alternative(child_state, class)
    |> Message.update_part(container_id, &%{&1 | body: {:multipart, sub_ids}})
    |> then(&{&1, state})
  end

  # A multipart/alternative that contained only text or only HTML parts
  # offers them as both bodies.
  defp fixup_alternative(
         message,
         %State{need_html: true, need_text: true} = child_state,
         :multipart_alternative
       ) do
    new_html = Enum.drop(message.html_body, child_state.html_parts)
    new_text = Enum.drop(message.text_body, child_state.text_parts)

    cond do
      new_text == [] and new_html != [] -> %{message | text_body: message.text_body ++ new_html}
      new_html == [] and new_text != [] -> %{message | html_body: message.html_body ++ new_text}
      true -> message
    end
  end

  defp fixup_alternative(message, _child_state, _class), do: message

  ## Leaf parts

  defp process_leaf(message, state, headers, content_type, disposition, flags, body, depth) do
    encoding = TransferEncoding.encoding_of(headers)
    {inline?, text?, class} = flags

    if class == :message and encoding == :none do
      # An unencoded nested message is delimited by the enclosing boundary,
      # so its raw content is exactly the remaining body chunk.
      add_nested_message(
        message,
        state,
        headers,
        content_type,
        disposition,
        :none,
        false,
        body,
        depth
      )
    else
      {bytes, encoding, problem?, inline?, text?, class} =
        case TransferEncoding.decode(body, encoding) do
          {:ok, bytes} -> {bytes, encoding, false, inline?, text?, class}
          :error -> {body, :none, true, false, true, :text_other}
        end

      if class == :message do
        add_encoded_message(
          message,
          state,
          headers,
          content_type,
          disposition,
          encoding,
          bytes,
          depth
        )
      else
        add_leaf(
          message,
          state,
          {headers, content_type, disposition, encoding, problem?},
          {inline?, text?, class},
          bytes
        )
      end
    end
  end

  defp add_nested_message(
         message,
         state,
         headers,
         content_type,
         disposition,
         encoding,
         problem?,
         raw,
         depth
       ) do
    nested =
      case parse_message(raw, depth) do
        {:ok, nested} -> nested
        :error -> %Message{raw_message: raw}
      end

    part = %Part{
      headers: headers,
      content_type: content_type,
      content_disposition: disposition,
      encoding: encoding,
      encoding_problem?: problem?,
      body: {:message, nested}
    }

    add_attachment_part(message, state, part)
  end

  # A base64 or quoted-printable encoded message/rfc822 part: decode, then
  # parse recursively while the nesting budget lasts.
  defp add_encoded_message(
         message,
         state,
         headers,
         content_type,
         disposition,
         encoding,
         bytes,
         depth
       ) do
    parsed = if depth > 0, do: parse_message(bytes, depth - 1), else: :error

    case parsed do
      {:ok, nested} ->
        part = %Part{
          headers: headers,
          content_type: content_type,
          content_disposition: disposition,
          encoding: encoding,
          body: {:message, nested}
        }

        add_attachment_part(message, state, part)

      :error ->
        part = %Part{
          headers: headers,
          content_type: content_type,
          content_disposition: disposition,
          encoding: encoding,
          encoding_problem?: true,
          body: {:binary, bytes}
        }

        add_attachment_part(message, state, part)
    end
  end

  defp add_attachment_part(message, state, part) do
    part_id = length(message.parts)

    message =
      %{message | attachments: message.attachments ++ [part_id]}
      |> Message.add_part(part)

    {message, state}
  end

  defp add_leaf(message, state, part_info, flags, bytes) do
    {headers, content_type, disposition, encoding, problem?} = part_info
    {inline?, text?, class} = flags

    inline? =
      inline? and
        not attachment_disposition?(disposition) and
        (state.parts == 1 or
           (state.mime != :multipart_related and
              (class == :inline or not ContentType.has_param?(content_type, "name"))))

    {add_html?, add_text?, state} = body_candidates(state, class, inline?)

    part_id = length(message.parts)

    {body, message} =
      if text? do
        text = Charset.to_utf8(bytes, ContentType.param(content_type, "charset"))
        html? = class == :text_html

        message =
          cond do
            add_html? and not html? -> %{message | html_body: message.html_body ++ [part_id]}
            add_text? and html? -> %{message | text_body: message.text_body ++ [part_id]}
            true -> message
          end

        message =
          cond do
            add_html? and html? -> %{message | html_body: message.html_body ++ [part_id]}
            add_text? and not html? -> %{message | text_body: message.text_body ++ [part_id]}
            true -> %{message | attachments: message.attachments ++ [part_id]}
          end

        {if(html?, do: {:html, text}, else: {:text, text}), message}
      else
        message =
          if add_html?, do: %{message | html_body: message.html_body ++ [part_id]}, else: message

        message =
          if add_text?, do: %{message | text_body: message.text_body ++ [part_id]}, else: message

        message = %{message | attachments: message.attachments ++ [part_id]}

        {if(inline?, do: {:inline_binary, bytes}, else: {:binary, bytes}), message}
      end

    part = %Part{
      headers: headers,
      content_type: content_type,
      content_disposition: disposition,
      encoding: encoding,
      encoding_problem?: problem?,
      body: body
    }

    {Message.add_part(message, part), state}
  end

  # Decides whether this part is a candidate for the text and/or HTML body.
  defp body_candidates(state, class, inline?) do
    cond do
      state.mime == :multipart_alternative ->
        case class do
          :text_html -> {true, false, state}
          :text_plain -> {false, true, state}
          _other -> {false, false, state}
        end

      inline? ->
        state =
          if state.in_alternative and (state.need_text or state.need_html) do
            case class do
              :text_html -> %{state | need_text: false}
              :text_plain -> %{state | need_html: false}
              _other -> state
            end
          else
            state
          end

        {state.need_html, state.need_text, state}

      true ->
        {false, false, state}
    end
  end

  defp attachment_disposition?(nil), do: false
  defp attachment_disposition?(%ContentType{type: type}), do: type == "attachment"

  defp find_structured(headers, name) do
    case Header.get(headers, name) do
      nil -> nil
      value -> ContentType.parse(value)
    end
  end

  ## MIME classification.
  #
  # Returns `{multipart?, inline?, text?, class}`. A part without a
  # Content-Type defaults to text/plain, or to message/rfc822 inside a
  # multipart/digest container.

  defp mime_class(nil, :multipart_digest), do: {false, false, false, :message}
  defp mime_class(nil, _parent), do: {false, true, true, :text_plain}

  defp mime_class(%ContentType{type: "multipart", subtype: subtype}, _parent),
    do: {true, false, false, multipart_class(subtype)}

  defp mime_class(%ContentType{type: "text", subtype: "plain"}, _parent),
    do: {false, true, true, :text_plain}

  defp mime_class(%ContentType{type: "text", subtype: "html"}, _parent),
    do: {false, true, true, :text_html}

  defp mime_class(%ContentType{type: "text"}, _parent), do: {false, false, true, :text_other}

  defp mime_class(%ContentType{type: type}, _parent) when type in ["image", "audio", "video"],
    do: {false, true, false, :inline}

  defp mime_class(%ContentType{type: "message", subtype: subtype}, _parent)
       when subtype in ["rfc822", "global"],
       do: {false, false, false, :message}

  defp mime_class(%ContentType{}, _parent), do: {false, false, false, :other}

  defp multipart_class("mixed"), do: :multipart_mixed
  defp multipart_class("alternative"), do: :multipart_alternative
  defp multipart_class("related"), do: :multipart_related
  defp multipart_class("digest"), do: :multipart_digest
  defp multipart_class(_other), do: :multipart_other

  ## Multipart body splitting

  # Splits a multipart body into the chunks between boundary delimiters.
  # Content before the first delimiter (the preamble) and after the closing
  # `--boundary--` delimiter (the epilogue) is discarded. Returns
  # `:not_found` when no delimiter appears in the body.
  defp split_multipart(body, boundary) do
    delimiter = "--" <> boundary

    positions =
      for {pos, _len} <- :binary.matches(body, delimiter),
          line_anchored?(body, pos),
          delimiter_line?(body, pos + byte_size(delimiter)),
          do: pos

    case positions do
      [] -> :not_found
      positions -> {:ok, build_chunks(body, byte_size(delimiter), positions)}
    end
  end

  defp line_anchored?(_body, 0), do: true
  defp line_anchored?(body, pos), do: :binary.at(body, pos - 1) == ?\n

  # After the boundary only a terminator (`--`), transport padding or a line
  # break may follow.
  defp delimiter_line?(body, offset) do
    cond do
      offset >= byte_size(body) -> true
      terminator?(body, offset) -> true
      :binary.at(body, offset) in [?\r, ?\n, ?\s, ?\t] -> true
      true -> false
    end
  end

  defp terminator?(body, offset),
    do: offset + 2 <= byte_size(body) and binary_part(body, offset, 2) == "--"

  defp build_chunks(body, delimiter_size, positions),
    do: build_chunks(body, delimiter_size, positions, [])

  defp build_chunks(_body, _delimiter_size, [], acc), do: Enum.reverse(acc)

  defp build_chunks(body, delimiter_size, [pos | rest], acc) do
    if terminator?(body, pos + delimiter_size) do
      Enum.reverse(acc)
    else
      start = start_of_next_line(body, pos + delimiter_size)

      stop =
        case rest do
          [next | _] -> strip_line_break_before(body, next)
          [] -> byte_size(body)
        end

      chunk = if stop > start, do: binary_part(body, start, stop - start), else: ""
      build_chunks(body, delimiter_size, rest, [chunk | acc])
    end
  end

  defp start_of_next_line(body, offset) do
    case :binary.match(body, "\n", scope: {offset, byte_size(body) - offset}) do
      {pos, _len} -> pos + 1
      :nomatch -> byte_size(body)
    end
  end

  # The line break preceding a boundary delimiter belongs to the delimiter
  # (RFC 2046), so it is not part of the chunk.
  defp strip_line_break_before(body, pos) do
    cond do
      pos >= 1 and :binary.at(body, pos - 1) == ?\n ->
        if pos >= 2 and :binary.at(body, pos - 2) == ?\r, do: pos - 2, else: pos - 1

      true ->
        pos
    end
  end
end
