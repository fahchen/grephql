defmodule Grephql.MixProject do
  use Mix.Project

  def project do
    [
      app: :grephql,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_parsec, "~> 1.4", runtime: false},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:ecto, "~> 3.12"},
      {:ecto_typed_schema, "~> 0.1.0"},
      {:mimic, "~> 2.3", only: :test}
    ]
  end
end
