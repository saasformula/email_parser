defmodule EmailParser.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/saasformula/email_parser"

  def project do
    [
      app: :email_parser,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Pure Elixir RFC 5322 / MIME email parser that extracts nested attachments",
      package: package(),
      docs: docs(),
      name: "EmailParser",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/v#{@version}/CHANGELOG.md"
      },
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        Structs: [EmailParser.Attachment, EmailParser.Email]
      ]
    ]
  end
end
