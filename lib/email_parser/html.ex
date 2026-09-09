defmodule EmailParser.Html do
  @moduledoc false
  # Renders an HTML body as plain text.
  #
  # This is not a layout engine: it drops markup, turns block-level elements
  # into line breaks and resolves character references, which is what
  # `EmailParser.strip_attachments/1` needs to offer a text body for a message
  # that carries only HTML.

  # Elements whose content is markup or metadata rather than prose.
  @dropped_elements ~w(script style head)

  # Elements that open a new line in the rendered text.
  @block_elements ~w(address article aside blockquote br dd div dl dt figure
                     footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p
                     pre section table td th tr ul)

  # The Latin-1 named references (HTML 4), which older mail clients still emit
  # for accented prose. They run in codepoint order from U+00A0, so the table
  # is built from the names; case matters here — `&Auml;` is not `&auml;`.
  @latin1_names ~w(nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo
                   not shy reg macr deg plusmn sup2 sup3 acute micro para middot cedil
                   sup1 ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc
                   Atilde Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave
                   Iacute Icirc Iuml ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times
                   Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig agrave aacute
                   acirc atilde auml aring aelig ccedil egrave eacute ecirc euml
                   igrave iacute icirc iuml eth ntilde ograve oacute ocirc otilde ouml
                   divide oslash ugrave uacute ucirc uuml yacute thorn yuml)

  # The markup delimiters, plus the punctuation a mail composer reaches for.
  # `nbsp` overrides the Latin-1 table: once the markup is gone a no-break
  # space is just a space, which is also how it is collapsed below.
  @other_entities %{
    "amp" => "&",
    "apos" => "'",
    "bull" => "\u2022",
    "euro" => "\u20AC",
    "gt" => ">",
    "hellip" => "\u2026",
    "ldquo" => "\u201C",
    "lsquo" => "\u2018",
    "lt" => "<",
    "mdash" => "\u2014",
    "nbsp" => " ",
    "ndash" => "\u2013",
    "quot" => "\"",
    "rdquo" => "\u201D",
    "rsquo" => "\u2019",
    "trade" => "\u2122"
  }

  @entities @latin1_names
            |> Enum.with_index(0xA0)
            |> Map.new(fn {name, code} -> {name, <<code::utf8>>} end)
            |> Map.merge(@other_entities)

  @spec to_text(String.t()) :: String.t()
  def to_text(html) when is_binary(html) do
    html
    |> render([])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> decode_entities()
    |> normalize_whitespace()
  end

  ## Markup removal

  defp render(html, acc) do
    case :binary.split(html, "<") do
      [text] -> [text | acc]
      [text, rest] -> element(rest, [text | acc])
    end
  end

  defp element("!--" <> rest, acc), do: render(skip_past(rest, "-->"), acc)

  defp element(rest, acc) do
    {tag, rest} = take_tag(rest)
    name = tag_name(tag)

    cond do
      name in @dropped_elements and not closing?(tag) -> render(skip_element(rest, name), acc)
      name in @block_elements -> render(rest, ["\n" | acc])
      true -> render(rest, acc)
    end
  end

  defp take_tag(rest) do
    case :binary.split(rest, ">") do
      [tag, remainder] -> {tag, remainder}
      [tag] -> {tag, ""}
    end
  end

  defp closing?(tag), do: String.starts_with?(tag, "/")

  defp tag_name(tag) do
    tag
    |> String.trim_leading("/")
    |> String.split([" ", "\t", "\r", "\n", "/"], parts: 2)
    |> hd()
    |> String.downcase(:ascii)
  end

  # Skips to just past the element's closing tag. Downcasing is ASCII-only, so
  # the match offset holds for the original binary whatever its contents.
  defp skip_element(rest, name) do
    case :binary.match(String.downcase(rest, :ascii), "</" <> name) do
      {pos, len} ->
        rest
        |> binary_part(pos + len, byte_size(rest) - pos - len)
        |> skip_past(">")

      :nomatch ->
        ""
    end
  end

  defp skip_past(binary, pattern) do
    case :binary.split(binary, pattern) do
      [_skipped, rest] -> rest
      [_unterminated] -> ""
    end
  end

  ## Character references

  defp decode_entities(text) do
    text
    |> entities([])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp entities(text, acc) do
    case :binary.split(text, "&") do
      [text] ->
        [text | acc]

      [text, rest] ->
        case :binary.split(rest, ";") do
          [name, remainder] ->
            case entity_value(name) do
              nil -> entities(rest, ["&", text | acc])
              value -> entities(remainder, [value, text | acc])
            end

          [_unterminated] ->
            [rest, "&", text | acc]
        end
    end
  end

  defp entity_value(<<"#x", hex::binary>>), do: codepoint(hex, 16)
  defp entity_value(<<"#X", hex::binary>>), do: codepoint(hex, 16)
  defp entity_value(<<"#", digits::binary>>), do: codepoint(digits, 10)
  defp entity_value(name), do: Map.get(@entities, name)

  defp codepoint(digits, base) do
    with {code, ""} <- Integer.parse(digits, base),
         true <- encodable?(code) do
      <<code::utf8>>
    else
      _invalid -> nil
    end
  end

  defp encodable?(code) do
    code in [?\t, ?\n, ?\r] or
      (code >= 0x20 and code <= 0x10FFFF and code not in 0xD800..0xDFFF)
  end

  ## Whitespace

  # Source indentation and line breaks are not content, so runs of spaces
  # collapse and only the breaks introduced by block elements survive.
  defp normalize_whitespace(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.split("\n")
    |> Enum.map(&collapse_spaces/1)
    |> collapse_blank_lines([])
    |> Enum.join("\n")
    |> String.trim()
  end

  defp collapse_spaces(line) do
    line
    |> String.split([" ", "\t", "\u00A0"], trim: true)
    |> Enum.join(" ")
  end

  defp collapse_blank_lines([], acc), do: Enum.reverse(acc)
  defp collapse_blank_lines(["" | rest], ["" | _] = acc), do: collapse_blank_lines(rest, acc)
  defp collapse_blank_lines([line | rest], acc), do: collapse_blank_lines(rest, [line | acc])
end
