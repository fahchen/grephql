defmodule TypedGql.Generation.Plugins.SkipInclude do
  @moduledoc """
  Built-in generation plugin for the `@include` and `@skip` directives.

  A conditionally-selected field may be omitted from the response, so its
  generated type must be nullable even when the schema says the field is
  non-null. Runtime decode already tolerates the omission; this plugin only
  fixes generated-type accuracy.

  After the `normalize` step has propagated ancestor (inline-fragment /
  fragment-spread) directives onto each field, this plugin walks the
  resolved tree and marks every conditionally-selected field nullable.

  ## Conditionality

  A directive's `if:` argument is a `TypedGql.Language.Variable` or a literal
  `TypedGql.Language.BooleanValue`:

    * `@include(if: $var)` / `@skip(if: $var)` — conditional (variable).
    * `@include(if: true)` / `@skip(if: false)` — no-op, not conditional.
    * `@include(if: false)` / `@skip(if: true)` — always omitted, but still
      generated as nullable to keep the struct shape stable.

  So `@include` is conditional unless `if:` is literal `true`, and `@skip`
  is conditional unless `if:` is literal `false`.

  List fields (`embeds_many`) are forced to `default: []` downstream, which
  cannot represent whole-absence as `nil`, so their nullability is left
  unchanged (see the type generator docs).
  """
  use TypedGql.Generation.Plugin

  alias TypedGql.Generation.Field
  alias TypedGql.Generation.Schema
  alias TypedGql.Language.BooleanValue
  alias TypedGql.Language.Variable

  @conditional_directives ~w(include skip)

  @impl TypedGql.Generation.Plugin
  def after_resolve(%Schema{} = tree, _context) do
    Schema.map_fields(tree, &maybe_mark_nullable/1)
  end

  defp maybe_mark_nullable(%Field{kind: :embeds_many} = field), do: field

  defp maybe_mark_nullable(%Field{} = field) do
    if conditional?(field.query_field.directives) do
      Field.put_nullable(field, true)
    else
      field
    end
  end

  @doc """
  Whether `directives` can remove the field from the response.

  `TypedGql.TypeGenerator` shares this when merging repeated selections: a copy
  that cannot be removed makes the merged field unconditional.
  """
  @spec conditional?([TypedGql.Language.Directive.t()]) :: boolean()
  def conditional?(directives) do
    Enum.any?(directives, fn directive ->
      directive.name in @conditional_directives and directive_omits?(directive)
    end)
  end

  defp directive_omits?(directive) do
    case if_arg_value(directive.arguments) do
      %Variable{} -> true
      %BooleanValue{value: value} -> conditional_literal?(directive.name, value)
      _other -> false
    end
  end

  # `@include(if: true)` and `@skip(if: false)` always select the field.
  defp conditional_literal?("include", true), do: false
  defp conditional_literal?("skip", false), do: false
  defp conditional_literal?(_name, _value), do: true

  defp if_arg_value(arguments) do
    case Enum.find(arguments, &(&1.name == "if")) do
      nil -> nil
      arg -> arg.value
    end
  end
end
