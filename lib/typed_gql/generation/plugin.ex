defmodule TypedGql.Generation.Plugin do
  @moduledoc """
  Behaviour for hooking into the response-type generation pipeline.

  Generation runs as four named steps — `normalize`, `resolve`, `lower`,
  `create`. Plugins observe/transform the output of the first three via
  `after_normalize`, `after_resolve`, and `after_lower` (plus
  `before_normalize` for the raw entry). Adjacent `before_X` equals
  `after_prev`, so only the `after_*` family and `before_normalize` are
  exposed. The terminal `create` step compiles modules and is not hookable.

  All callbacks are optional. `use TypedGql.Generation.Plugin` provides
  identity defaults and `defoverridable`, so a plugin only implements the
  hooks it cares about (the built-in `@include`/`@skip` plugin implements
  only `after_resolve`).

  TypedGql always runs its built-in plugins — currently
  `TypedGql.Generation.Plugins.SkipInclude` for `@include`/`@skip` — before the
  ones given in the `:generation_plugins` option, in order, at each juncture.

  `TypedGql.TypeGenerator` describes what each step does.

  A `TypedGql.Language` node reaching a callback carries the line and column of
  the *file* it was written in, not its position within the document, so that
  the module generated from it can record where it came from. A node from a
  document that does not map onto the file — anything but a `~GQL` sigil written
  at the call site — carries neither. Validation, whose messages count from the
  document, has already run by then.
  """

  alias TypedGql.Generation.Context
  alias TypedGql.Generation.Schema
  alias TypedGql.Language

  @typedoc """
  What `Module.create/3` is handed to record where a generated module came
  from: the caller's `Macro.Env`, or a keyword list carrying `:file`/`:line`.
  """
  # TODO: replace with `Module.create_opts()` once the minimum Elixir is 1.19,
  # which is where that type was added; mix.exs still allows `~> 1.15`.
  @type module_create_opts() :: Macro.Env.t() | keyword()

  @type selection() ::
          Language.Field.t()
          | Language.InlineFragment.t()
          | Language.FragmentSpread.t()

  @doc """
  Runs on the raw selections before normalization.
  """
  @callback before_normalize([selection()], Context.t()) :: [selection()]

  @doc """
  Runs on the canonical selections produced by normalization (fragment
  spreads expanded, inline fragments flattened, ancestor directives
  propagated onto each field).
  """
  @callback after_normalize([selection()], Context.t()) :: [selection()]

  @doc """
  Runs on the generated-schema tree produced by resolution.

  This is where directive plugins like `@include`/`@skip` operate, since
  it is the last juncture before field types are lowered.
  """
  @callback after_resolve(Schema.t(), Context.t()) :: Schema.t()

  @doc """
  Runs on the `{module, quoted_ast, create_opts}` triples produced by lowering,
  where `create_opts` is what `Module.create/3` is handed to record where the
  generated module came from.

  Treat `create_opts` as opaque and per triple: each module records the location
  of the node it came from, so rebuilding the triples with one captured value
  would collapse every module onto a single line.
  """
  @callback after_lower([{module(), Macro.t(), module_create_opts()}], Context.t()) ::
              [{module(), Macro.t(), module_create_opts()}]

  @optional_callbacks before_normalize: 2, after_normalize: 2, after_resolve: 2, after_lower: 2

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour TypedGql.Generation.Plugin

      @impl TypedGql.Generation.Plugin
      def before_normalize(selections, _context), do: selections

      @impl TypedGql.Generation.Plugin
      def after_normalize(selections, _context), do: selections

      @impl TypedGql.Generation.Plugin
      def after_resolve(schema, _context), do: schema

      @impl TypedGql.Generation.Plugin
      def after_lower(module_asts, _context), do: module_asts

      defoverridable before_normalize: 2,
                     after_normalize: 2,
                     after_resolve: 2,
                     after_lower: 2
    end
  end
end
