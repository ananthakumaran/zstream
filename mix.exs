defmodule Zstream.Mixfile do
  use Mix.Project

  @source_url "https://github.com/ananthakumaran/zstream"
  @version "0.6.1"

  def project do
    [
      app: :zstream,
      version: @version,
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      description: "Streaming zip file writer and reader",
      package: package(),
      docs: docs(),
      dialyzer: [
        plt_add_deps: :transitive,
        flags: [:unmatched_returns, :race_conditions, :error_handling, :underspecs]
      ],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:temp, "~> 0.4", only: :test, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    %{
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Anantha Kumaran <ananthakumaran@gmail.com>"]
    }
  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end
end
