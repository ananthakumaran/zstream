defmodule Zstream.Mixfile do
  use Mix.Project

  def project do
    [
      app: :zstream,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
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
      {:temp, "~> 0.4", only: :test}
    ]
  end
end
