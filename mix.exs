defmodule Zstream.Mixfile do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :zstream,
      version: @version,
      elixir: "~> 1.4",
      start_permanent: Mix.env == :prod,
      description: "Streaming zip file writer",
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
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:temp, "~> 0.4", only: :test},
      {:ex_doc, "~> 0.18", only: :dev},
    ]
  end

  defp package do
    %{licenses: ["MIT"],
      links: %{"Github" => "https://github.com/ananthakumaran/zstream"},
      maintainers: ["ananthakumaran@gmail.com"]}
  end

  defp docs do
    [source_url: "https://github.com/ananthakumaran/zstream",
     source_ref: "v#{@version}",
     main: Zstream,
     extras: ["README.md"]]
  end
end
