defmodule TypedGql.InputTypeGeneratorTest do
  use ExUnit.Case, async: true

  # Suppress warnings for modules created at runtime by InputTypeGenerator
  @compile {:no_warn_undefined,
            [
              TypedGql.Test.Input.Basic.Inputs.CreateUserInput,
              TypedGql.Test.Input.Build.Inputs.CreateUserInput,
              TypedGql.Test.Input.Required.Inputs.CreateUserInput,
              TypedGql.Test.Input.Nullable.Inputs.CreateUserInput,
              TypedGql.Test.Input.Nested.Inputs.CreateUserInput,
              TypedGql.Test.Input.Nested.Inputs.AddressInput,
              TypedGql.Test.Input.NestedBuild.Inputs.CreateUserInput,
              TypedGql.Test.Input.Deep.Inputs.CreateOrderInput,
              TypedGql.Test.Input.Deep.Inputs.OrderItemInput,
              TypedGql.Test.Input.Deep.Inputs.PriceInput,
              TypedGql.Test.Input.DeepBuild.Inputs.CreateOrderInput,
              TypedGql.Test.Input.DeepBuild.Inputs.OrderItemInput,
              TypedGql.Test.Input.DeepBuild.Inputs.PriceInput,
              TypedGql.Test.Input.DeepReq.Inputs.CreateOrderInput,
              TypedGql.Test.Input.DeepReq.Inputs.OrderItemInput,
              TypedGql.Test.Input.DeepReq.Inputs.PriceInput,
              TypedGql.Test.Input.DeepDump.Inputs.CreateOrderInput,
              TypedGql.Test.Input.DeepDump.Inputs.OrderItemInput,
              TypedGql.Test.Input.DeepDump.Inputs.PriceInput,
              TypedGql.Test.Input.Dedup.Inputs.SharedInput,
              TypedGql.Test.Input.EmbedSource.Inputs.UpdateProfileInput,
              TypedGql.Test.Input.EmbedSource.Inputs.AddressInput,
              TypedGql.Test.Input.EmbedSource.Inputs.JobInput,
              TypedGql.Test.Input.EmbedSource.Inputs.GeoPointInput,
              TypedGql.Test.Input.EmbedEmpty.Inputs.UpdateProfileInput,
              TypedGql.Test.Input.EmbedEmpty.Inputs.AddressInput,
              TypedGql.Test.Input.EmbedEmpty.Inputs.JobInput,
              TypedGql.Test.Input.EmbedEmpty.Inputs.GeoPointInput,
              TypedGql.Test.Var.EmbedSource.Inputs.AddressInput,
              TypedGql.Test.Var.EmbedSource.Inputs.GeoPointInput,
              TypedGql.Test.Var.EmbedSource.UpdateProfile.Variables,
              TypedGql.Test.Var.IdField.GetUser.Variables,
              TypedGql.Test.Var.Scalar.GetUser.Variables,
              TypedGql.Test.Var.Required.GetUser.Variables,
              TypedGql.Test.Var.Camel.GetUser.Variables,
              TypedGql.Test.Var.Embed.Inputs.CreateUserInput,
              TypedGql.Test.Var.Embed.CreateUser.Variables,
              TypedGql.Test.Var.Mixed.Inputs.CreateUserInput,
              TypedGql.Test.Var.Mixed.CreateUser.Variables,
              TypedGql.Test.Var.Dump.Inputs.CreateUserInput,
              TypedGql.Test.Var.Dump.CreateUser.Variables,
              TypedGql.Test.Var.Params.GetUser.Variables,
              TypedGql.Test.Var.ParamsEmbed.Inputs.CreateUserInput,
              TypedGql.Test.Var.ParamsEmbed.CreateUser.Variables,
              TypedGql.Test.Input.Params.Inputs.CreateUserInput
            ]}

  import TypedGql.Test.Helpers, only: [errors_on: 2]

  alias TypedGql.InputTypeGenerator
  alias TypedGql.Schema.Field, as: SchemaField
  alias TypedGql.Schema.InputValue
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper

  describe "basic input type generation" do
    test "generates embedded schema for input type with scalar fields" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Input.Basic,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert TypedGql.Test.Input.Basic.Inputs.CreateUserInput in modules

      fields = TypedGql.Test.Input.Basic.Inputs.CreateUserInput.__schema__(:fields)
      assert :name in fields
      assert :email in fields
    end

    test "build/1 succeeds with valid params" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Input.Build,
        scalar_types: %{},
        caller_env: __ENV__
      )

      assert {:ok, struct} =
               TypedGql.Test.Input.Build.Inputs.CreateUserInput.build(%{
                 name: "Alice",
                 email: "a@b.com"
               })

      assert struct.name == "Alice"
      assert struct.email == "a@b.com"
    end

    test "build/1 fails when required field is missing" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Input.Required,
        scalar_types: %{},
        caller_env: __ENV__
      )

      assert {:error, changeset} =
               TypedGql.Test.Input.Required.Inputs.CreateUserInput.build(%{email: "a@b.com"})

      assert "can't be blank" in errors_on(changeset, :name)
    end

    test "nullable field defaults to nil" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Input.Nullable,
        scalar_types: %{},
        caller_env: __ENV__
      )

      assert {:ok, struct} =
               TypedGql.Test.Input.Nullable.Inputs.CreateUserInput.build(%{name: "Alice"})

      assert struct.email == nil
    end
  end

  describe "nested input types" do
    test "generates nested input type with embeds_one" do
      schema = schema_with_nested_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Input.Nested,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert TypedGql.Test.Input.Nested.Inputs.CreateUserInput in modules
      assert TypedGql.Test.Input.Nested.Inputs.AddressInput in modules

      assert :address in TypedGql.Test.Input.Nested.Inputs.CreateUserInput.__schema__(:embeds)
    end

    test "build/1 with nested input succeeds" do
      schema = schema_with_nested_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Input.NestedBuild,
        scalar_types: %{},
        caller_env: __ENV__
      )

      assert {:ok, struct} =
               TypedGql.Test.Input.NestedBuild.Inputs.CreateUserInput.build(%{
                 name: "Alice",
                 address: %{city: "NYC", street: "123 Main St"}
               })

      assert struct.name == "Alice"
      assert struct.address.city == "NYC"
      assert struct.address.street == "123 Main St"
    end
  end

  describe "deeply nested input types" do
    test "generates 3-level deep input with list and enum" do
      schema = schema_with_deep_input()

      operation =
        parse!(
          "mutation CreateOrder($input: CreateOrderInput!) { createOrder(input: $input) { id } }"
        )

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Input.Deep,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert TypedGql.Test.Input.Deep.Inputs.CreateOrderInput in modules
      assert TypedGql.Test.Input.Deep.Inputs.OrderItemInput in modules
      assert TypedGql.Test.Input.Deep.Inputs.PriceInput in modules

      # Level 1 → Level 2: embeds_many
      assert :items in TypedGql.Test.Input.Deep.Inputs.CreateOrderInput.__schema__(:embeds)

      # Level 2 → Level 3: embeds_one
      assert :price in TypedGql.Test.Input.Deep.Inputs.OrderItemInput.__schema__(:embeds)
    end

    test "build/1 with 3-level deep nested input succeeds" do
      schema = schema_with_deep_input()

      operation =
        parse!(
          "mutation CreateOrder($input: CreateOrderInput!) { createOrder(input: $input) { id } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Input.DeepBuild,
        scalar_types: %{},
        caller_env: __ENV__
      )

      assert {:ok, struct} =
               TypedGql.Test.Input.DeepBuild.Inputs.CreateOrderInput.build(%{
                 note: "rush",
                 items: [
                   %{
                     product_name: "Widget",
                     quantity: 2,
                     price: %{amount: "19.99", currency: "USD"}
                   },
                   %{
                     product_name: "Gadget",
                     quantity: 1,
                     price: %{amount: "49.99", currency: "EUR"}
                   }
                 ]
               })

      assert struct.note == "rush"
      assert length(struct.items) == 2

      [first, second] = struct.items
      assert first.product_name == "Widget"
      assert first.quantity == 2
      assert first.price.amount == "19.99"
      assert first.price.currency == :usd

      assert second.product_name == "Gadget"
      assert second.price.currency == :eur
    end

    test "build/1 rejects missing required fields in deeply nested input" do
      schema = schema_with_deep_input()

      operation =
        parse!(
          "mutation CreateOrder($input: CreateOrderInput!) { createOrder(input: $input) { id } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Input.DeepReq,
        scalar_types: %{},
        caller_env: __ENV__
      )

      assert {:error, changeset} =
               TypedGql.Test.Input.DeepReq.Inputs.CreateOrderInput.build(%{
                 items: [%{quantity: 1, price: %{amount: "10"}}]
               })

      item_changeset = hd(changeset.changes.items)
      assert "can't be blank" in errors_on(item_changeset, :product_name)

      price_changeset = item_changeset.changes.price
      assert "can't be blank" in errors_on(price_changeset, :currency)
    end

    test "dump/1 serializes deeply nested input to camelCase JSON" do
      schema = schema_with_deep_input()

      operation =
        parse!(
          "mutation CreateOrder($input: CreateOrderInput!) { createOrder(input: $input) { id } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Input.DeepDump,
        scalar_types: %{},
        caller_env: __ENV__
      )

      {:ok, struct} =
        TypedGql.Test.Input.DeepDump.Inputs.CreateOrderInput.build(%{
          note: "test",
          items: [%{product_name: "A", quantity: 1, price: %{amount: "5", currency: "USD"}}]
        })

      dumped = Ecto.embedded_dump(struct, :json)
      assert dumped[:note] == "test"

      [item] = dumped[:items]
      assert item[:productName] == "A"
      assert item[:quantity] == 1
      assert item[:price][:amount] == "5"
      assert item[:price][:currency] == "USD"
    end
  end

  describe "camelCase embed fields" do
    test "dump/1 uses GraphQL field name for nested input object fields" do
      schema = schema_with_camel_embed_input()

      operation =
        parse!(
          "mutation UpdateProfile($input: UpdateProfileInput!) { updateProfile(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Input.EmbedSource,
        scalar_types: %{},
        caller_env: __ENV__
      )

      {:ok, struct} =
        TypedGql.Test.Input.EmbedSource.Inputs.UpdateProfileInput.build(%{
          home_address: %{city: "NYC", geo_point: %{lat_degrees: "40.7"}},
          past_jobs: [%{title: "Dev"}]
        })

      dumped = Ecto.embedded_dump(struct, :json)

      assert dumped[:homeAddress][:city] == "NYC"
      assert dumped[:homeAddress][:geoPoint][:latDegrees] == "40.7"
      assert [%{title: "Dev"}] = dumped[:pastJobs]
      refute Map.has_key?(dumped, :home_address)
      refute Map.has_key?(dumped, :past_jobs)
    end

    test "dump/1 uses GraphQL variable name for input object variables" do
      schema = schema_with_camel_embed_input()

      operation =
        parse!(
          "mutation UpdateProfile($homeAddress: AddressInput!) { updateProfile(input: $homeAddress) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Var.EmbedSource,
        scalar_types: %{},
        caller_env: __ENV__
      )

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.EmbedSource,
          function_name: :update_profile,
          scalar_types: %{},
          caller_env: __ENV__
        )

      {:ok, vars} = variables_module.build(%{home_address: %{city: "NYC"}})

      dumped = Ecto.embedded_dump(vars, :json)

      assert dumped[:homeAddress][:city] == "NYC"
      refute Map.has_key?(dumped, :home_address)
    end

    test "omitted nullable embeds_many dumps as an empty list" do
      schema = schema_with_camel_embed_input()

      operation =
        parse!(
          "mutation UpdateProfile($input: UpdateProfileInput!) { updateProfile(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Input.EmbedEmpty,
        scalar_types: %{},
        caller_env: __ENV__
      )

      {:ok, struct} =
        TypedGql.Test.Input.EmbedEmpty.Inputs.UpdateProfileInput.build(%{
          home_address: %{city: "NYC"}
        })

      dumped = Ecto.embedded_dump(struct, :json)

      assert dumped[:pastJobs] == []
      assert dumped[:homeAddress][:geoPoint] == nil
    end
  end

  describe "deduplication" do
    test "same input type referenced twice generates only once" do
      schema = schema_with_shared_input()

      operation =
        parse!("mutation Op($a: SharedInput!, $b: SharedInput!) { doA(input: $a) { name } }")

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Input.Dedup,
          scalar_types: %{},
          caller_env: __ENV__
        )

      shared_count = Enum.count(modules, &(&1 == TypedGql.Test.Input.Dedup.Inputs.SharedInput))
      assert shared_count == 1
    end
  end

  describe "scalar-only variables are skipped" do
    test "does not generate modules for scalar variables" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($id: ID!) { user(id: $id) { name } }")

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Input.Scalar,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert modules == []
    end

    test "a variable type missing from the schema is treated as a scalar" do
      schema = SchemaHelper.build_schema()
      operation = parse!(~s|query Q($when: Unknown) { user(id: "1") { name } }|)

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Input.UnknownScalar,
          function_name: :q,
          scalar_types: %{"Unknown" => TypedGql.Types.DateTime},
          caller_env: __ENV__
        )

      assert :when in variables_module.__schema__(:fields)
      assert variables_module.__schema__(:type, :when) == TypedGql.Types.DateTime
    end
  end

  # Ecto.Embedded, which carries nested lists on the output side, implements only
  # load/3 and dump/3 — a variables struct is built through a changeset.
  describe "nested input object lists" do
    test "a list of lists of input objects is refused with a reason" do
      schema = SchemaHelper.build_schema(types: types_with_nested_input())
      operation = parse!("query Q($f: [[Filter]]) { find(filters: $f) }")

      assert_raise CompileError, ~r/not a list of lists/, fn ->
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Input.NestedList,
          function_name: :q,
          scalar_types: %{},
          caller_env: __ENV__
        )
      end
    end

    test "a single list of input objects still generates an embed" do
      schema = SchemaHelper.build_schema(types: types_with_nested_input())
      operation = parse!("query Q($f: [Filter]) { find(filters: $f) }")

      module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Input.FlatList,
          function_name: :q,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert :f in module.__schema__(:embeds)
    end
  end

  describe "generate_variables/3" do
    test "$id variable does not conflict with Ecto primary key" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($id: ID!) { user(id: $id) { name } }")

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.IdField,
          function_name: :get_user,
          scalar_types: %{},
          caller_env: __ENV__
        )

      # No auto-generated primary key
      assert variables_module.__schema__(:primary_key) == []

      # :id is a regular castable field
      assert {:ok, vars} = variables_module.build(%{id: "42"})
      assert vars.id == "42"

      # Serializes correctly
      assert %{id: "42"} = Ecto.embedded_dump(vars, :json)
    end

    test "generates Variables struct with scalar fields" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($id: ID!) { user(id: $id) { name } }")

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.Scalar,
          function_name: :get_user,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert variables_module == TypedGql.Test.Var.Scalar.GetUser.Variables

      fields = variables_module.__schema__(:fields)
      assert :id in fields
    end

    test "build/1 validates required scalar variables" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($id: ID!) { user(id: $id) { name } }")

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.Required,
          function_name: :get_user,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert {:ok, vars} = variables_module.build(%{id: "123"})
      assert vars.id == "123"

      assert {:error, changeset} = variables_module.build(%{})
      assert "can't be blank" in errors_on(changeset, :id)
    end

    test "returns nil for operations without variables" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name } }")

      assert nil ==
               InputTypeGenerator.generate_variables(operation, schema,
                 client_module: TypedGql.Test.Var.NoVars,
                 function_name: :get_user,
                 scalar_types: %{},
                 caller_env: __ENV__
               )
    end

    test "uses source mapping for camelCase variable names" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($userId: ID!) { user(id: $userId) { name } }")

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.Camel,
          function_name: :get_user,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert {:ok, vars} = variables_module.build(%{user_id: "123"})
      assert vars.user_id == "123"

      dumped = Ecto.embedded_dump(vars, :json)
      assert dumped[:userId] == "123"
    end

    test "embeds input object variables" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Var.Embed,
        scalar_types: %{},
        caller_env: __ENV__
      )

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.Embed,
          function_name: :create_user,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert variables_module == TypedGql.Test.Var.Embed.CreateUser.Variables
      assert :input in variables_module.__schema__(:embeds)

      assert {:ok, vars} =
               variables_module.build(%{input: %{name: "Alice", email: "a@b.com"}})

      assert vars.input.name == "Alice"
    end

    test "mixes scalar and input object variables" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($id: ID!, $input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Var.Mixed,
        scalar_types: %{},
        caller_env: __ENV__
      )

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.Mixed,
          function_name: :create_user,
          scalar_types: %{},
          caller_env: __ENV__
        )

      fields = variables_module.__schema__(:fields)
      embeds = variables_module.__schema__(:embeds)
      assert :id in fields
      assert :input in embeds

      assert {:ok, vars} =
               variables_module.build(%{id: "1", input: %{name: "Alice"}})

      assert vars.id == "1"
      assert vars.input.name == "Alice"
    end

    test "embedded_dump serializes correctly for GraphQL" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Var.Dump,
        scalar_types: %{},
        caller_env: __ENV__
      )

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.Dump,
          function_name: :create_user,
          scalar_types: %{},
          caller_env: __ENV__
        )

      {:ok, vars} = variables_module.build(%{input: %{name: "Alice", email: "a@b.com"}})
      dumped = Ecto.embedded_dump(vars, :json)

      assert dumped[:input][:name] == "Alice"
      assert dumped[:input][:email] == "a@b.com"
    end
  end

  describe "params() type generation" do
    test "Variables module with params() compiles successfully" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($id: ID!) { user(id: $id) { name } }")

      # params() type is injected at compilation — if this doesn't raise, it compiled
      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.Params,
          function_name: :get_user,
          scalar_types: %{},
          caller_env: __ENV__
        )

      # Module is functional with build/1
      assert {:ok, vars} = variables_module.build(%{id: "123"})
      assert vars.id == "123"
    end

    test "Input type modules with params() compile successfully" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Input.Params,
          scalar_types: %{},
          caller_env: __ENV__
        )

      input_module = hd(modules)
      assert {:ok, _struct} = input_module.build(%{name: "Alice"})
    end

    test "Variables with embed params() compiles and builds correctly" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Var.ParamsEmbed,
        scalar_types: %{},
        caller_env: __ENV__
      )

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: TypedGql.Test.Var.ParamsEmbed,
          function_name: :create_user,
          scalar_types: %{},
          caller_env: __ENV__
        )

      assert {:ok, vars} = variables_module.build(%{input: %{name: "Alice"}})
      assert vars.input.name == "Alice"
    end
  end

  # Helpers

  defp parse!(query) do
    {:ok, %{definitions: [operation | _rest]}} = TypedGql.Parser.parse(query)
    operation
  end

  defp schema_with_input do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Mutation" => %Type{
          kind: :object,
          name: "Mutation",
          fields: %{
            "createUser" => %SchemaField{
              name: "createUser",
              type: %TypeRef{kind: :object, name: "User"},
              args: %{
                "input" => %InputValue{
                  name: "input",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :input_object, name: "CreateUserInput"}
                  }
                }
              }
            }
          }
        },
        "CreateUserInput" => %Type{
          kind: :input_object,
          name: "CreateUserInput",
          input_fields: %{
            "name" => %InputValue{
              name: "name",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :scalar, name: "String"}
              }
            },
            "email" => %InputValue{
              name: "email",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types, mutation_type: "Mutation")
  end

  defp schema_with_nested_input do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Mutation" => %Type{
          kind: :object,
          name: "Mutation",
          fields: %{
            "createUser" => %SchemaField{
              name: "createUser",
              type: %TypeRef{kind: :object, name: "User"},
              args: %{
                "input" => %InputValue{
                  name: "input",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :input_object, name: "CreateUserInput"}
                  }
                }
              }
            }
          }
        },
        "CreateUserInput" => %Type{
          kind: :input_object,
          name: "CreateUserInput",
          input_fields: %{
            "name" => %InputValue{
              name: "name",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :scalar, name: "String"}
              }
            },
            "address" => %InputValue{
              name: "address",
              type: %TypeRef{kind: :input_object, name: "AddressInput"}
            }
          }
        },
        "AddressInput" => %Type{
          kind: :input_object,
          name: "AddressInput",
          input_fields: %{
            "city" => %InputValue{
              name: "city",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :scalar, name: "String"}
              }
            },
            "street" => %InputValue{
              name: "street",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types, mutation_type: "Mutation")
  end

  defp schema_with_deep_input do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Mutation" => %Type{
          kind: :object,
          name: "Mutation",
          fields: %{
            "createOrder" => %SchemaField{
              name: "createOrder",
              type: %TypeRef{kind: :object, name: "Order"},
              args: %{
                "input" => %InputValue{
                  name: "input",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :input_object, name: "CreateOrderInput"}
                  }
                }
              }
            }
          }
        },
        "Order" => %Type{
          kind: :object,
          name: "Order",
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            }
          }
        },
        "CreateOrderInput" => %Type{
          kind: :input_object,
          name: "CreateOrderInput",
          input_fields: %{
            "note" => %InputValue{
              name: "note",
              type: %TypeRef{kind: :scalar, name: "String"}
            },
            "items" => %InputValue{
              name: "items",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{
                  kind: :list,
                  of_type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :input_object, name: "OrderItemInput"}
                  }
                }
              }
            }
          }
        },
        "OrderItemInput" => %Type{
          kind: :input_object,
          name: "OrderItemInput",
          input_fields: %{
            "productName" => %InputValue{
              name: "productName",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :scalar, name: "String"}
              }
            },
            "quantity" => %InputValue{
              name: "quantity",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :scalar, name: "Int"}
              }
            },
            "price" => %InputValue{
              name: "price",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :input_object, name: "PriceInput"}
              }
            }
          }
        },
        "PriceInput" => %Type{
          kind: :input_object,
          name: "PriceInput",
          input_fields: %{
            "amount" => %InputValue{
              name: "amount",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :scalar, name: "String"}
              }
            },
            "currency" => %InputValue{
              name: "currency",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :enum, name: "Currency"}
              }
            }
          }
        },
        "Currency" => %Type{
          kind: :enum,
          name: "Currency",
          enum_values: [
            %{name: "USD", is_deprecated: false, deprecation_reason: nil},
            %{name: "EUR", is_deprecated: false, deprecation_reason: nil},
            %{name: "JPY", is_deprecated: false, deprecation_reason: nil}
          ]
        }
      })

    SchemaHelper.build_schema(types: types, mutation_type: "Mutation")
  end

  defp schema_with_camel_embed_input do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Mutation" => %Type{
          kind: :object,
          name: "Mutation",
          fields: %{
            "updateProfile" => %SchemaField{
              name: "updateProfile",
              type: %TypeRef{kind: :object, name: "User"},
              args: %{
                "input" => %InputValue{
                  name: "input",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :input_object, name: "UpdateProfileInput"}
                  }
                }
              }
            }
          }
        },
        "UpdateProfileInput" => %Type{
          kind: :input_object,
          name: "UpdateProfileInput",
          input_fields: %{
            "homeAddress" => %InputValue{
              name: "homeAddress",
              type: %TypeRef{kind: :input_object, name: "AddressInput"}
            },
            "pastJobs" => %InputValue{
              name: "pastJobs",
              type: %TypeRef{
                kind: :list,
                of_type: %TypeRef{
                  kind: :non_null,
                  of_type: %TypeRef{kind: :input_object, name: "JobInput"}
                }
              }
            }
          }
        },
        "AddressInput" => %Type{
          kind: :input_object,
          name: "AddressInput",
          input_fields: %{
            "city" => %InputValue{
              name: "city",
              type: %TypeRef{kind: :scalar, name: "String"}
            },
            "geoPoint" => %InputValue{
              name: "geoPoint",
              type: %TypeRef{kind: :input_object, name: "GeoPointInput"}
            }
          }
        },
        "GeoPointInput" => %Type{
          kind: :input_object,
          name: "GeoPointInput",
          input_fields: %{
            "latDegrees" => %InputValue{
              name: "latDegrees",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        },
        "JobInput" => %Type{
          kind: :input_object,
          name: "JobInput",
          input_fields: %{
            "title" => %InputValue{
              name: "title",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types, mutation_type: "Mutation")
  end

  defp schema_with_shared_input do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Mutation" => %Type{
          kind: :object,
          name: "Mutation",
          fields: %{
            "doA" => %SchemaField{
              name: "doA",
              type: %TypeRef{kind: :object, name: "User"},
              args: %{
                "input" => %InputValue{
                  name: "input",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :input_object, name: "SharedInput"}
                  }
                }
              }
            }
          }
        },
        "SharedInput" => %Type{
          kind: :input_object,
          name: "SharedInput",
          input_fields: %{
            "value" => %InputValue{
              name: "value",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types, mutation_type: "Mutation")
  end

  defp types_with_nested_input do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "find" => %SchemaField{
            name: "find",
            type: %TypeRef{kind: :scalar, name: "String"},
            args: %{
              "filters" => %InputValue{
                name: "filters",
                type: %TypeRef{
                  kind: :list,
                  of_type: %TypeRef{kind: :input_object, name: "Filter"}
                }
              }
            }
          }
        }
      },
      "Filter" => %Type{
        kind: :input_object,
        name: "Filter",
        input_fields: %{
          "term" => %InputValue{name: "term", type: %TypeRef{kind: :scalar, name: "String"}}
        }
      }
    })
  end
end
