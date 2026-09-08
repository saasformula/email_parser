defmodule EmailParser.MixProject do
  use Mix.Project

  @source_url "https://github.com/saasformula/email_parser"

  def project do
    [
      app: :email_parser,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: [],
      description: "Pure Elixir RFC 5322 / MIME email parser that extracts nested attachments",
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
