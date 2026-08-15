defmodule TypedGql.MixProject do
  use Mix.Project

  @version "0.12.2"
  @source_url "https://github.com/fahchen/typed_gql"

  def project do
    [
      app: :typed_gql,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      compilers: [:yecc] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      test_coverage: test_coverage(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "TypedGql",
      source_url: @source_url
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:nimble_parsec, "~> 1.4", runtime: false},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4", optional: true},
      {:ecto, "~> 3.12"},
      {:ecto_typed_schema, "~> 0.1"},
      {:typed_structor, "~> 0.6"},
      {:plug, "~> 1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Compile-time GraphQL client for Elixir. Validates queries at compilation, generates typed Ecto embedded schemas, and executes via Req."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Hex" => "https://hex.pm/packages/typed_gql"
      },
      files:
        ~w(lib guides priv/graphql/introspection.graphql src/*.yrl .formatter.exs mix.exs README.md LICENSE NOTICE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        {"README.md", [title: "Introduction"]},
        {"guides/mapping-custom-scalars.md", [title: "Mapping Custom Scalars"]},
        {"guides/extending-requests-with-prepare-req.md",
         [title: "Customizing Requests with prepare_req"]},
        {"LICENSE", [title: "License"]}
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      skip_undefined_reference_warnings_on: [
        "TypedGql.TypeMapper",
        "TypedGql.TypeGenerator",
        "TypedGql.InputTypeGenerator"
      ],
      groups_for_modules: [
        "Core API": [
          TypedGql,
          TypedGql.Macros,
          TypedGql.Query,
          TypedGql.Result,
          TypedGql.Error,
          TypedGql.DecodeError,
          TypedGql.OperationInfo,
          TypedGql.JSON
        ],
        "Type System": [
          TypedGql.EmbeddedSchema,
          TypedGql.ResponseDecoder,
          TypedGql.VariablesDumper,
          TypedGql.TypeMapper,
          TypedGql.TypeGenerator,
          TypedGql.InputTypeGenerator,
          TypedGql.Types.DateTime,
          TypedGql.Types.Enum,
          TypedGql.Types.Union,
          TypedGql.Types.PathSegment,
          TypedGql.Types.Typename
        ],
        "Generation Plugins": [
          TypedGql.Generation.Plugin,
          TypedGql.Generation.Context,
          TypedGql.Generation.Schema,
          TypedGql.Generation.Field
        ],
        Formatting: [
          TypedGql.Formatter
        ],
        "Mix Tasks": [
          Mix.Tasks.TypedGql.DownloadSchema
        ]
      ]
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
        "test --cover"
      ]
    ]
  end

  defp test_coverage do
    [
      summary: [threshold: 100],
      # TypedGql.JSON picks between JSON, Jason and a runtime-configured library;
      # a single test run can only ever exercise one of those branches.
      ignore_modules: [
        TypedGql.Parser,
        TypedGql.JSON,
        :typed_gql_parser,
        ~r/^TypedGql\.Test(\.|$)/
      ]
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts/typed_gql.plt",
      plt_core_path: "priv/plts/core.plt",
      plt_add_apps: [:ex_unit, :mix]
    ]
  end
end
