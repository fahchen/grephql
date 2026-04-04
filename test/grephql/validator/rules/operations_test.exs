defmodule Grephql.Validator.Rules.OperationsTest do
  use ExUnit.Case, async: true

  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator.Context
  alias Grephql.Validator.Rules.Operations

  defp parse!(query) do
    {:ok, doc} = Grephql.Parser.parse(query)
    doc
  end

  defp validate(query, schema_opts \\ []) do
    schema = SchemaHelper.build_schema(schema_opts)
    ctx = %Context{schema: schema}
    Operations.validate(parse!(query), ctx)
  end

  defp errors(ctx), do: Context.errors_by_severity(ctx, :error)

  describe "root type validation" do
    test "valid query passes" do
      ctx = validate("query { user { name } }")
      assert errors(ctx) == []
    end

    test "mutation without mutation root type fails" do
      ctx = validate("mutation { createUser { id } }")
      assert [error] = errors(ctx)
      assert error.message =~ "mutations"
    end

    test "mutation with mutation root type passes" do
      ctx = validate("mutation { createUser { id } }", mutation_type: "Mutation")
      assert errors(ctx) == []
    end

    test "subscription without subscription root type fails" do
      ctx = validate("subscription { onUser { name } }")
      assert [error] = errors(ctx)
      assert error.message =~ "subscriptions"
    end

    test "subscription with subscription root type passes" do
      ctx =
        validate("subscription { onUser { name } }", subscription_type: "Subscription")

      assert errors(ctx) == []
    end
  end

  describe "anonymous operation validation" do
    test "single anonymous operation passes" do
      ctx = validate("{ user { name } }")
      assert errors(ctx) == []
    end

    test "multiple anonymous operations fail" do
      ctx = validate("{ user { name } } { user { email } }")

      assert [error] = errors(ctx)
      assert error.message =~ "only one anonymous operation"
    end
  end

  describe "unique operation names" do
    test "unique names pass" do
      ctx = validate("query GetUser { user { name } } query ListUsers { users { name } }")
      assert errors(ctx) == []
    end

    test "duplicate names fail" do
      ctx = validate("query GetUser { user { name } } query GetUser { user { email } }")
      assert [error] = errors(ctx)
      assert error.message =~ "duplicate operation name \"GetUser\""
    end
  end
end
