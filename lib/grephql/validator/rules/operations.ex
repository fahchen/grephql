defmodule Grephql.Validator.Rules.Operations do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Language.OperationDefinition
  alias Grephql.Validator.Context
  alias Grephql.Validator.Helpers

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{} = ctx) do
    operations = Enum.filter(definitions, &match?(%OperationDefinition{}, &1))

    ctx
    |> validate_root_types(operations)
    |> validate_anonymous_operations(operations)
    |> validate_unique_names(operations)
  end

  defp validate_root_types(ctx, operations) do
    Enum.reduce(operations, ctx, fn op, acc ->
      validate_root_type(acc, op)
    end)
  end

  defp validate_root_type(ctx, %OperationDefinition{operation: :query} = op) do
    if ctx.schema.query_type do
      ctx
    else
      Context.add_error(ctx, "schema does not support queries", line: Helpers.loc_line(op))
    end
  end

  defp validate_root_type(ctx, %OperationDefinition{operation: :mutation} = op) do
    if ctx.schema.mutation_type do
      ctx
    else
      Context.add_error(ctx, "schema does not support mutations", line: Helpers.loc_line(op))
    end
  end

  defp validate_root_type(ctx, %OperationDefinition{operation: :subscription} = op) do
    if ctx.schema.subscription_type do
      ctx
    else
      Context.add_error(ctx, "schema does not support subscriptions", line: Helpers.loc_line(op))
    end
  end

  defp validate_anonymous_operations(ctx, operations) do
    anonymous_count =
      Enum.count(operations, &is_nil(&1.name))

    if anonymous_count > 1 do
      Context.add_error(ctx, "only one anonymous operation is allowed")
    else
      ctx
    end
  end

  defp validate_unique_names(ctx, operations) do
    operations
    |> Enum.reject(&is_nil(&1.name))
    |> Enum.group_by(& &1.name)
    |> Enum.reduce(ctx, fn
      {_name, [_single]}, acc ->
        acc

      {name, [_first | _rest]}, acc ->
        Context.add_error(acc, "duplicate operation name \"#{name}\"")
    end)
  end
end
