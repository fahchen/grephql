defmodule Grephql.MixProject do
  use Mix.Project

  def project do
    [
      app: :grephql,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      compilers: [:yecc] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer()
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_parsec, "~> 1.4", runtime: false},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:ecto, "~> 3.12"},
      {:ecto_typed_schema, "~> 0.1.0"},
      {:typed_structor, "~> 0.6"},
      {:plug, "~> 1.0", only: :test},
      {:mimic, "~> 2.3", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "dialyzer",
        "test"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts/grephql.plt",
      plt_core_path: "priv/plts/core.plt",
      plt_add_apps: [:ex_unit, :mix]
    ]
  end
end
