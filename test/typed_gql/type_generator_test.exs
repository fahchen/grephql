defmodule TypedGql.TypeGeneratorTest do
  use ExUnit.Case, async: true

  # These modules are dynamically defined by TypeGenerator.generate/3 at test
  # runtime, so the compiler cannot see them when compiling this test file.
  @compile {:no_warn_undefined,
            [
              TypedGql.Test.Alias.GetUser.Result.User,
              TypedGql.Test.AliasArgs.GetUsers.Result,
              TypedGql.Test.AliasArgs.GetUsers.Result.Author,
              TypedGql.Test.AliasArgs.GetUsers.Result.Editor,
              TypedGql.Test.AliasMulti.GetUsers.Result,
              TypedGql.Test.AliasMulti.GetUsers.Result.Author,
              TypedGql.Test.AliasMulti.GetUsers.Result.SimpleUser,
              TypedGql.Test.AutoTypename.GetNode.Result.Node.User,
              TypedGql.Test.FragmentNoPlugins.Fragments.UserFields,
              TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.AppSubscription,
              TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.Shop,
              TypedGql.Test.Isolation.GetUser.Result.User,
              TypedGql.Test.Isolation.ListUsers.Result.User,
              TypedGql.Test.ListEmbed.GetUser.Result.User,
              TypedGql.Test.Nested.GetUser.Result.User,
              TypedGql.Test.NoDupTypename.GetNode.Result.Node.User,
              TypedGql.Test.NoPK.GetUser.Result.User,
              TypedGql.Test.NonNull.GetUser.Result.User,
              TypedGql.Test.ObjectInlineFrag.GetUser.Result.User,
              TypedGql.Test.ObjectTypename.GetUser.Result.User,
              TypedGql.Test.ResultRoot.GetUser.Result,
              TypedGql.Test.ResultRoot.GetUser.Result.User,
              TypedGql.Test.Union.Search.Result.Search.Post,
              TypedGql.Test.Union.Search.Result.Search.User,
              TypedGql.Test.UnionField.Search.Result.Result,
              TypedGql.Test.UnionSharedOnly.Search.Result.Search,
              TypedGql.Test.PartialUnion.Search.Result,
              TypedGql.Test.PartialUnion.Search.Result.Search.Post,
              TypedGql.Test.AbstractCondition.Search.Result,
              TypedGql.Test.AbstractCondition.Search.Result.Search.Post,
              TypedGql.Test.SpreadCondition.Search.Result.Search.Post,
              TypedGql.Test.SpreadCondition.Search.Result.Search.User,
              TypedGql.Test.GhostCondition.Search.Result.Search.User,
              TypedGql.Test.UnusableTypename.Search.Result,
              TypedGql.Test.UnusableTypename.Search.Result.Search.User,
              TypedGql.Test.Covariant.Search.Result.Search.User.Friend,
              TypedGql.Test.Introspection.Introspect.Result.Schema.QueryType,
              TypedGql.Test.NestedAbstract.Search.Result.Search.Post,
              TypedGql.Test.NestedAbstract.Search.Result.Search.User,
              TypedGql.Test.AbstractSpread.Search.Result.Search.User,
              TypedGql.Test.SharedSpread.Search.Result,
              TypedGql.Test.SharedSpread.Search.Result.Search,
              TypedGql.Test.OverlappingConditions.Search.Result.Search.User,
              TypedGql.Test.ImplementedInterface.GetNode.Result,
              TypedGql.Test.ImplementedInterface.GetNode.Result.Node,
              TypedGql.Test.MergedSubSelections.Search.Result.Search.User.Profile,
              TypedGql.Test.PartialInterface.Search.Result.Search.Post,
              TypedGql.Test.PartialInterface.Search.Result.Search.User,
              TypedGql.Test.TransitiveInterface.GetNode.Result,
              TypedGql.Test.TransitiveInterface.GetNode.Result.Node,
              TypedGql.Test.EqualArgs.Search.Result,
              TypedGql.Test.EqualObjectArgs.Search.Result
            ]}

  alias TypedGql.Schema.Field, as: SchemaField
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.TypeGenerator

  defmodule CaptureTreePlugin do
    @moduledoc false
    use TypedGql.Generation.Plugin

    @impl TypedGql.Generation.Plugin
    def after_resolve(tree, _context) do
      send(self(), {:resolved_tree, tree})
      tree
    end
  end

  describe "basic scalar fields" do
    test "generates embedded schema with scalar fields" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name email } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Basic,
          function_name: :get_user
        )

      assert TypedGql.Test.Basic.GetUser.Result.User in modules

      user = struct(TypedGql.Test.Basic.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end

    test "non-null field uses null: false" do
      types = types_with_non_null_name()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.NonNull,
        function_name: :get_user
      )

      fields = TypedGql.Test.NonNull.GetUser.Result.User.__schema__(:fields)
      assert :name in fields
    end

    test "nullable field defaults to nil" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name email } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Nullable,
        function_name: :get_user
      )

      user = struct(TypedGql.Test.Nullable.GetUser.Result.User)
      assert user.name == nil
      assert user.email == nil
    end
  end

  describe "generated module list" do
    test "first returned module is the operation Result root" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name email } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.ResultRoot,
          function_name: :get_user
        )

      # Compiler.compile_document!/4 uses hd(output_modules) as the decode root.
      assert hd(modules) == TypedGql.Test.ResultRoot.GetUser.Result
    end
  end

  describe "inline fragment on an object parent" do
    test "abstract-typed inline fragment with a nested fragment flattens without crashing" do
      schema = schema_object_with_interface()
      operation = parse!("query { user(id: \"1\") { ... on Node { id ... { name } } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.ObjectInlineFrag,
          function_name: :get_user
        )

      assert TypedGql.Test.ObjectInlineFrag.GetUser.Result.User in modules

      fields = TypedGql.Test.ObjectInlineFrag.GetUser.Result.User.__schema__(:fields)
      assert :id in fields
      assert :name in fields
    end
  end

  describe "generation lifecycle hooks" do
    defmodule RecordingPlugin do
      @moduledoc false
      use TypedGql.Generation.Plugin

      @impl TypedGql.Generation.Plugin
      def before_normalize(selections, _context) do
        send(self(), :before_normalize)
        selections
      end

      @impl TypedGql.Generation.Plugin
      def after_normalize(selections, _context) do
        send(self(), :after_normalize)
        selections
      end

      @impl TypedGql.Generation.Plugin
      def after_lower(module_asts, _context) do
        send(self(), :after_lower)
        module_asts
      end
    end

    test "the pipeline invokes before_normalize, after_normalize, and after_lower" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.HookOrder,
        function_name: :get_user,
        generation_plugins: [RecordingPlugin]
      )

      assert_received :before_normalize
      assert_received :after_normalize
      assert_received :after_lower
    end
  end

  describe "nested object fields" do
    test "generates nested embedded schema with embeds_one" do
      types = types_with_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name posts { title } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Nested,
          function_name: :get_user
        )

      assert TypedGql.Test.Nested.GetUser.Result.User in modules
      assert TypedGql.Test.Nested.GetUser.Result.User.Posts in modules

      assert :posts in TypedGql.Test.Nested.GetUser.Result.User.__schema__(:embeds)
    end

    test "deeply nested objects generate full path" do
      types = types_with_author()
      schema = SchemaHelper.build_schema(types: types)

      operation =
        parse!("query { user(id: \"1\") { name posts { title author { name } } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Deep,
          function_name: :get_user
        )

      assert TypedGql.Test.Deep.GetUser.Result.User in modules
      assert TypedGql.Test.Deep.GetUser.Result.User.Posts in modules
      assert TypedGql.Test.Deep.GetUser.Result.User.Posts.Author in modules
    end

    test "list field generates embeds_many" do
      types = types_with_list_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name posts { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.ListEmbed,
        function_name: :get_user
      )

      assert :posts in TypedGql.Test.ListEmbed.GetUser.Result.User.__schema__(:embeds)
    end
  end

  describe "response key collisions" do
    test "two aliases that underscore to the same struct field are rejected" do
      schema = SchemaHelper.build_schema()
      operation = parse!(~s|query { user(id: "1") { typeName: __typename type_name: id } }|)

      assert_raise CompileError, ~r/both map to the struct field :type_name/, fn ->
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.KeyCollision,
          function_name: :get_user
        )
      end
    end
  end

  describe "root introspection fields" do
    test "__schema resolves against the introspection types" do
      schema = schema_with_introspection()
      operation = parse!("query { __schema { queryType { name } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Introspection,
        function_name: :introspect
      )

      assert :name in TypedGql.Test.Introspection.Introspect.Result.Schema.QueryType.__schema__(
               :fields
             )
    end
  end

  describe "field alias support" do
    test "alias affects struct field name" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { display_name: name email } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Alias,
        function_name: :get_user
      )

      fields = TypedGql.Test.Alias.GetUser.Result.User.__schema__(:fields)
      assert :display_name in fields
      refute :name in fields
    end

    test "multiple aliases of the same field generate independent structs" do
      schema = SchemaHelper.build_schema()

      operation =
        parse!(
          ~s|query { author: user(id: "1") { name email } simpleUser: user(id: "1") { name } }|
        )

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.AliasMulti,
          function_name: :get_users
        )

      assert TypedGql.Test.AliasMulti.GetUsers.Result in modules
      assert TypedGql.Test.AliasMulti.GetUsers.Result.Author in modules
      assert TypedGql.Test.AliasMulti.GetUsers.Result.SimpleUser in modules

      # Each alias gets its own struct with its own selected fields
      author_fields = TypedGql.Test.AliasMulti.GetUsers.Result.Author.__schema__(:fields)
      assert :name in author_fields
      assert :email in author_fields

      simple_fields = TypedGql.Test.AliasMulti.GetUsers.Result.SimpleUser.__schema__(:fields)
      assert :name in simple_fields
      refute :email in simple_fields

      # Result has both alias fields
      result_fields = TypedGql.Test.AliasMulti.GetUsers.Result.__schema__(:fields)
      assert :author in result_fields
      assert :simple_user in result_fields
    end

    test "same field aliased with different arguments: independent structs, both arg sets printed, decode by alias" do
      schema = SchemaHelper.build_schema()

      query =
        ~s|query { author: user(id: "1") { name email } editor: user(id: "2") { name } }|

      {:ok, doc} = TypedGql.Parser.parse(query)
      operation = hd(doc.definitions)

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.AliasArgs,
          function_name: :get_users
        )

      result_mod = TypedGql.Test.AliasArgs.GetUsers.Result

      # Generation: one struct per alias, each with only its own selected fields
      assert result_mod in modules
      assert TypedGql.Test.AliasArgs.GetUsers.Result.Author in modules
      assert TypedGql.Test.AliasArgs.GetUsers.Result.Editor in modules

      author_fields = TypedGql.Test.AliasArgs.GetUsers.Result.Author.__schema__(:fields)
      assert :name in author_fields
      assert :email in author_fields

      editor_fields = TypedGql.Test.AliasArgs.GetUsers.Result.Editor.__schema__(:fields)
      assert :name in editor_fields
      refute :email in editor_fields

      result_fields = result_mod.__schema__(:fields)
      assert :author in result_fields
      assert :editor in result_fields

      # Printer: both distinct argument sets survive query reconstruction
      printed = TypedGql.Printer.print(doc)
      assert printed =~ ~s|author: user(id: "1")|
      assert printed =~ ~s|editor: user(id: "2")|

      # Decode: response keyed by alias loads into the matching nested struct
      data = %{
        "author" => %{"name" => "A", "email" => "a@x"},
        "editor" => %{"name" => "E"}
      }

      result = TypedGql.ResponseDecoder.decode!(result_mod, data)
      assert result.author.name == "A"
      assert result.author.email == "a@x"
      assert result.editor.name == "E"
    end

    test "alias affects nested module name" do
      types = types_with_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { articles: posts { title } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.AliasNested,
          function_name: :get_user
        )

      assert TypedGql.Test.AliasNested.GetUser.Result.User.Articles in modules
      refute TypedGql.Test.AliasNested.GetUser.Result.User.Posts in modules
    end
  end

  describe "per-query isolation" do
    test "different queries for same type get independent structs" do
      schema = SchemaHelper.build_schema()

      op1 = parse!("query { user(id: \"1\") { name email } }")

      TypeGenerator.generate(op1, schema,
        client_module: TypedGql.Test.Isolation,
        function_name: :get_user
      )

      op2 = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(op2, schema,
        client_module: TypedGql.Test.Isolation,
        function_name: :list_users
      )

      get_fields = TypedGql.Test.Isolation.GetUser.Result.User.__schema__(:fields)
      list_fields = TypedGql.Test.Isolation.ListUsers.Result.User.__schema__(:fields)

      assert :name in get_fields
      assert :email in get_fields
      assert :name in list_fields
      refute :email in list_fields
    end
  end

  describe "no primary key" do
    test "generated schemas have no :id field" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.NoPK,
        function_name: :get_user
      )

      fields = TypedGql.Test.NoPK.GetUser.Result.User.__schema__(:fields)
      refute :id in fields
    end
  end

  describe "union/interface with inline fragments" do
    test "generates per-fragment structs with shared fields merged" do
      schema = schema_with_union()

      operation =
        parse!("query { search { __typename id ... on User { email } ... on Post { title } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Union,
          function_name: :search
        )

      assert TypedGql.Test.Union.Search.Result in modules
      assert TypedGql.Test.Union.Search.Result.Search.User in modules
      assert TypedGql.Test.Union.Search.Result.Search.Post in modules

      # User struct has shared fields + own fields
      user_fields = TypedGql.Test.Union.Search.Result.Search.User.__schema__(:fields)
      assert :__typename in user_fields
      assert :id in user_fields
      assert :email in user_fields

      # Post struct has shared fields + own fields
      post_fields = TypedGql.Test.Union.Search.Result.Search.Post.__schema__(:fields)
      assert :__typename in post_fields
      assert :id in post_fields
      assert :title in post_fields
    end

    test "a union selected without inline fragments generates a plain object" do
      schema = schema_with_union()
      operation = parse!("query { search { __typename } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.UnionSharedOnly,
          function_name: :search
        )

      assert TypedGql.Test.UnionSharedOnly.Search.Result.Search in modules

      search_module = TypedGql.Test.UnionSharedOnly.Search.Result.Search
      assert :__typename in search_module.__schema__(:fields)

      # No variant module was generated, so __typename still has to accept every
      # member of the union.
      assert {:parameterized, {TypedGql.Types.Typename, values}} =
               search_module.__schema__(:type, :__typename)

      assert values == %{"User" => :user, "Post" => :post}
    end

    test "__typename on a concrete object type is that type's own name" do
      schema = SchemaHelper.build_schema()
      operation = parse!(~s|query { user(id: "1") { __typename name } }|)

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.ObjectTypename,
        function_name: :get_user
      )

      assert {:parameterized, {TypedGql.Types.Typename, %{"User" => :user}}} =
               TypedGql.Test.ObjectTypename.GetUser.Result.User.__schema__(:type, :__typename)
    end

    test "union field uses parameterized type, not embed" do
      schema = schema_with_union()

      operation =
        parse!("query { search { __typename ... on User { email } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.UnionField,
        function_name: :search
      )

      # search field should be a regular field (parameterized type), not an embed
      result_module = Module.safe_concat(TypedGql.Test.UnionField.Search, Result)
      embeds = result_module.__schema__(:embeds)
      refute :search in embeds

      fields = result_module.__schema__(:fields)
      assert :search in fields
    end

    test "end-to-end decode with union field" do
      schema = schema_with_union()

      operation =
        parse!("query { search { __typename id ... on User { email } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.UnionE2E,
        function_name: :search
      )

      json = %{
        "search" => [
          %{"__typename" => "User", "id" => "1", "email" => "a@b.com"},
          %{"__typename" => "Post", "id" => "2", "title" => "Hello"}
        ]
      }

      result = TypedGql.ResponseDecoder.decode!(TypedGql.Test.UnionE2E.Search.Result, json)

      [user, post] = result.search
      assert %{__struct__: TypedGql.Test.UnionE2E.Search.Result.Search.User} = user
      assert user.id == "1"
      assert user.email == "a@b.com"
      assert %{__struct__: TypedGql.Test.UnionE2E.Search.Result.Search.Post} = post
      assert post.id == "2"
      assert post.title == "Hello"
    end

    test "auto-injects __typename when not queried" do
      schema = schema_with_single_union()

      operation =
        parse!("query { node { ... on User { name } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.AutoTypename,
        function_name: :get_node
      )

      # __typename is auto-injected into each fragment struct
      user_fields = TypedGql.Test.AutoTypename.GetNode.Result.Node.User.__schema__(:fields)
      assert :__typename in user_fields

      json = %{"node" => %{"__typename" => "User", "name" => "Alice"}}
      result = TypedGql.ResponseDecoder.decode!(TypedGql.Test.AutoTypename.GetNode.Result, json)

      assert %{__struct__: TypedGql.Test.AutoTypename.GetNode.Result.Node.User} = result.node
      assert result.node.name == "Alice"
    end

    test "does not duplicate __typename when already queried" do
      schema = schema_with_single_union()

      operation =
        parse!("query { node { __typename ... on User { name } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.NoDupTypename,
        function_name: :get_node
      )

      user_fields = TypedGql.Test.NoDupTypename.GetNode.Result.Node.User.__schema__(:fields)
      typename_count = Enum.count(user_fields, &(&1 == :__typename))
      assert typename_count == 1
    end

    test "handles __typename when not in introspection fields" do
      schema = schema_with_interface_no_typename()

      operation =
        parse!(
          "query($id: ID!) { node(id: $id) { ... on AppSubscription { status } ... on Shop { name } } }"
        )

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.InterfaceNoTypename,
          function_name: :get_node
        )

      assert TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.AppSubscription in modules
      assert TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.Shop in modules

      # __typename is auto-injected and resolved even without it in the schema fields
      sub_fields =
        TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.AppSubscription.__schema__(:fields)

      assert :__typename in sub_fields
      assert :status in sub_fields

      shop_fields =
        TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.Shop.__schema__(:fields)

      assert :__typename in shop_fields
      assert :name in shop_fields

      # End-to-end decode works
      json = %{"node" => %{"__typename" => "AppSubscription", "status" => "ACTIVE"}}

      result =
        TypedGql.ResponseDecoder.decode!(
          TypedGql.Test.InterfaceNoTypename.GetNode.Result,
          json
        )

      assert %{__struct__: TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.AppSubscription} =
               result.node

      assert result.node.status == "ACTIVE"
    end

    test "single union field (not list) uses field with union type" do
      schema = schema_with_single_union()

      operation =
        parse!("query { node { __typename ... on User { name } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.SingleUnion,
        function_name: :get_node
      )

      json = %{"node" => %{"__typename" => "User", "name" => "Alice"}}
      result = TypedGql.ResponseDecoder.decode!(TypedGql.Test.SingleUnion.GetNode.Result, json)

      assert %{__struct__: TypedGql.Test.SingleUnion.GetNode.Result.Node.User} = result.node
      assert result.node.name == "Alice"
    end

    test "a member with no inline fragment still decodes, carrying the shared fields" do
      schema = schema_with_union()
      operation = parse!("query { search { __typename id ... on User { email } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.PartialUnion,
        function_name: :search
      )

      json = %{"search" => [%{"__typename" => "Post", "id" => "7"}]}
      result = TypedGql.ResponseDecoder.decode!(TypedGql.Test.PartialUnion.Search.Result, json)

      assert [%{__struct__: TypedGql.Test.PartialUnion.Search.Result.Search.Post} = post] =
               result.search

      assert post.id == "7"
    end

    test "an abstract type condition applies to every member it covers" do
      schema = schema_with_union_of_nodes()
      operation = parse!("query { search { __typename ... on Node { id } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.AbstractCondition,
        function_name: :search
      )

      json = %{"search" => [%{"__typename" => "Post", "id" => "7"}]}

      result =
        TypedGql.ResponseDecoder.decode!(TypedGql.Test.AbstractCondition.Search.Result, json)

      assert [%{__struct__: TypedGql.Test.AbstractCondition.Search.Result.Search.Post} = post] =
               result.search

      assert post.id == "7"
    end

    test "a named fragment spread keeps its type condition" do
      schema = schema_with_union()

      {:ok, %{definitions: [fragment]}} =
        TypedGql.Parser.parse("fragment UserFields on User { email }")

      operation = parse!("query { search { __typename ...UserFields } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.SpreadCondition,
        function_name: :search,
        fragments: %{
          "UserFields" => %{source: "", fragment: fragment, result_module: nil}
        }
      )

      user_fields = TypedGql.Test.SpreadCondition.Search.Result.Search.User.__schema__(:fields)
      post_fields = TypedGql.Test.SpreadCondition.Search.Result.Search.Post.__schema__(:fields)

      # `email` belongs to the User variant only; Post keeps just the shared field.
      assert :email in user_fields
      refute :email in post_fields
    end

    test "a fragment nested inside an abstract one reaches the concrete member" do
      schema = schema_with_union_of_nodes()

      operation =
        parse!("query { search { __typename ... on Node { id ... on User { email } } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.NestedAbstract,
        function_name: :search
      )

      user_fields = TypedGql.Test.NestedAbstract.Search.Result.Search.User.__schema__(:fields)
      post_fields = TypedGql.Test.NestedAbstract.Search.Result.Search.Post.__schema__(:fields)

      assert :id in user_fields
      assert :email in user_fields
      assert :id in post_fields
      refute :email in post_fields
    end

    test "a named abstract fragment spread carrying inline fragments still resolves" do
      schema = schema_with_union()

      {:ok, %{definitions: [fragment]}} =
        TypedGql.Parser.parse(
          "fragment SearchFields on SearchResult { __typename ... on User { email } }"
        )

      operation = parse!("query { search { ...SearchFields } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.AbstractSpread,
        function_name: :search,
        fragments: %{"SearchFields" => %{source: "", fragment: fragment, result_module: nil}}
      )

      user_fields = TypedGql.Test.AbstractSpread.Search.Result.Search.User.__schema__(:fields)
      assert :__typename in user_fields
      assert :email in user_fields
    end

    test "an interface spread of shared fields alone stays a plain object" do
      schema = schema_with_union_of_nodes()

      {:ok, %{definitions: [fragment]}} =
        TypedGql.Parser.parse("fragment ResultFields on SearchResult { __typename }")

      operation = parse!("query { search { ...ResultFields } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.SharedSpread,
        function_name: :search,
        fragments: %{"ResultFields" => %{source: "", fragment: fragment, result_module: nil}}
      )

      # A plain embed, not a __typename-dispatched union: a shared-only selection
      # needs no variants, and forcing dispatch would demand a discriminator the
      # response has no reason to carry.
      assert :search in TypedGql.Test.SharedSpread.Search.Result.__schema__(:embeds)

      assert :__typename in TypedGql.Test.SharedSpread.Search.Result.Search.__schema__(:fields)
    end

    test "the transmitted document carries the injected __typename" do
      schema = schema_with_union()

      document =
        TypedGql.EnsureTypename.transform(
          parse_document!("query { search { ... on User { email } } }"),
          schema
        )

      printed = TypedGql.Printer.print(document)

      # Without this the server never returns the discriminator the generated
      # decoder dispatches on.
      assert printed =~ "__typename"
    end

    test "a selection that already dispatches is left alone, and SDL passes through" do
      schema = schema_with_union()

      already =
        TypedGql.EnsureTypename.transform(
          parse_document!("query { search { __typename ... on User { email } } }"),
          schema
        )

      printed = TypedGql.Printer.print(already)
      assert printed |> String.split("__typename") |> length() == 2

      # A type system definition has no selection set to walk.
      sdl = parse_document!("scalar DateTime")
      assert TypedGql.EnsureTypename.transform(sdl, schema) == sdl
    end

    test "a covariant field keeps resolving when its type narrows to a member" do
      schema = schema_covariant_interface()

      operation =
        parse!("query { search { __typename ... on Node { friend { ... on User { email } } } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Covariant,
        function_name: :search
      )

      # User.friend narrows Node.friend to User, so the inline fragment left over
      # from normalizing under Node has to be flattened against User.
      assert :email in TypedGql.Test.Covariant.Search.Result.Search.User.Friend.__schema__(
               :fields
             )
    end

    test "an aliased or conditional __typename does not serve as the discriminator" do
      schema = schema_with_union()

      operation =
        parse!(
          "query Q($hide: Boolean!) { search { kind: __typename __typename @skip(if: $hide) ... on User { email } } }"
        )

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.UnusableTypename,
        function_name: :search
      )

      # Neither copy can be dispatched on, so a plain one is added alongside.
      fields = TypedGql.Test.UnusableTypename.Search.Result.Search.User.__schema__(:fields)
      assert :kind in fields
      assert :__typename in fields

      json = %{"search" => [%{"__typename" => "User", "kind" => "User", "email" => "a@b.com"}]}

      result =
        TypedGql.ResponseDecoder.decode!(TypedGql.Test.UnusableTypename.Search.Result, json)

      assert [%{__struct__: TypedGql.Test.UnusableTypename.Search.Result.Search.User}] =
               result.search
    end

    test "the same field selected by two overlapping conditions is merged once" do
      schema = schema_with_two_interfaces()

      operation =
        parse!("query { search { __typename ... on Node { id } ... on Named { id name } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.OverlappingConditions,
        function_name: :search
      )

      fields = TypedGql.Test.OverlappingConditions.Search.Result.Search.User.__schema__(:fields)

      assert Enum.count(fields, &(&1 == :id)) == 1
      assert :name in fields
    end

    test "sub-selections of a field reached by two conditions are merged" do
      schema = schema_with_two_interfaces()

      operation =
        parse!(
          "query { search { __typename ... on Node { profile { bio } } ... on Named { profile { avatar } } } }"
        )

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.MergedSubSelections,
        function_name: :search
      )

      profile_fields =
        TypedGql.Test.MergedSubSelections.Search.Result.Search.User.Profile.__schema__(:fields)

      assert :bio in profile_fields
      assert :avatar in profile_fields
    end

    test "an unconditional copy of a merged field clears the other's @skip" do
      schema = schema_with_two_interfaces()

      tree =
        resolved_tree(
          schema,
          "query Q($show: Boolean!) { search { __typename ... on Node { id @include(if: $show) } ... on Named { id } } }",
          TypedGql.Test.MergedUnconditional
        )

      merged = variant_field(tree, "User", :id)
      refute merged.resolved.nullable
      assert merged.query_field.directives == []
    end

    test "a merged field conditional on both sides stays conditional" do
      schema = schema_with_two_interfaces()

      tree =
        resolved_tree(
          schema,
          "query Q($a: Boolean!, $b: Boolean!) { search { __typename ... on Node { id @include(if: $a) } ... on Named { id @skip(if: $b) } } }",
          TypedGql.Test.MergedConditional
        )

      merged = variant_field(tree, "User", :id)
      assert merged.resolved.nullable
      # Both conditions survive the merge; keeping only the first would also
      # leave the field nullable, so count them.
      assert length(merged.query_field.directives) == 2
    end

    test "a no-op @include(if: true) copy makes the merged field unconditional" do
      schema = schema_with_two_interfaces()

      tree =
        resolved_tree(
          schema,
          "query Q($a: Boolean!) { search { __typename ... on Node { id @include(if: $a) } ... on Named { id @include(if: true) } } }",
          TypedGql.Test.MergedNoOpDirective
        )

      # `@include(if: true)` always selects, so the merged field is always there.
      refute variant_field(tree, "User", :id).resolved.nullable
    end

    test "the same response key naming two different fields is rejected" do
      schema = schema_with_two_interfaces()

      operation =
        parse!("query { search { __typename ... on Named { x: id x: name } } }")

      assert_raise CompileError, ~r/names both "id" and "name"/, fn ->
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.ConflictingKey,
          function_name: :search
        )
      end
    end

    test "the same field selected with different arguments is rejected" do
      schema = schema_with_two_interfaces()

      operation =
        parse!(~s|query { user(id: "1") { name } user(id: "2") { name } }|)

      assert_raise CompileError, ~r/different arguments/, fn ->
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.ConflictingArgs,
          function_name: :get_user
        )
      end
    end

    test "the same field selected twice with equal arguments merges" do
      schema = schema_with_two_interfaces()

      # Same arguments, written twice and in different order — identical
      # selections, not a conflict.
      operation =
        parse!(
          ~s|query { search(first: 1, after: "a") { __typename } search(after: "a", first: 1) { __typename } }|
        )

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.EqualArgs,
        function_name: :search
      )

      assert :search in TypedGql.Test.EqualArgs.Search.Result.__schema__(:embeds)
    end

    test "input object arguments compare by field, not by written order" do
      schema = schema_with_two_interfaces()

      # Input object fields are unordered per the spec, so these are one
      # selection, not a conflict.
      operation =
        parse!(
          ~s|query { search(where: {a: 1, b: 2}) { __typename } search(where: {b: 2, a: 1}) { __typename } }|
        )

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.EqualObjectArgs,
        function_name: :search
      )

      assert :search in TypedGql.Test.EqualObjectArgs.Search.Result.__schema__(:embeds)
    end

    test "an interface that covers only some members still produces variants" do
      schema = schema_partial_interface()
      operation = parse!("query { search { __typename ... on Named { name } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.PartialInterface,
        function_name: :search
      )

      # Named covers User but not Post, so hoisting would hand `name` to Post too.
      user_fields = TypedGql.Test.PartialInterface.Search.Result.Search.User.__schema__(:fields)
      post_fields = TypedGql.Test.PartialInterface.Search.Result.Search.Post.__schema__(:fields)

      assert :name in user_fields
      refute :name in post_fields
    end

    test "an interface implemented through another interface is still shared" do
      schema = schema_transitive_interfaces()
      operation = parse!("query { node { ... on Base { id } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.TransitiveInterface,
        function_name: :get_node
      )

      # Parent implements Mid, Mid implements Base — so Parent declares `id` and
      # no dispatch is needed.
      assert :node in TypedGql.Test.TransitiveInterface.GetNode.Result.__schema__(:embeds)
      assert :id in TypedGql.Test.TransitiveInterface.GetNode.Result.Node.__schema__(:fields)
    end

    test "a fragment on an interface the parent implements stays a plain object" do
      schema = schema_interface_implementing_interface()
      operation = parse!("query { node { ... on Node { id } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.ImplementedInterface,
        function_name: :get_node
      )

      # Resolved against Timestamped, which declares `id` because it implements
      # Node — no variants and no discriminator the response would have to carry.
      assert :node in TypedGql.Test.ImplementedInterface.GetNode.Result.__schema__(:embeds)
      assert :id in TypedGql.Test.ImplementedInterface.GetNode.Result.Node.__schema__(:fields)
    end

    # Rules.Fragments rejects this before generation runs, but generate/3 is
    # public and does not validate, so it degrades instead of crashing.
    test "a type condition the schema does not declare contributes to no member" do
      schema = schema_with_union()
      operation = parse!("query { search { __typename ... on Ghost { id } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.GhostCondition,
        function_name: :search
      )

      fields = TypedGql.Test.GhostCondition.Search.Result.Search.User.__schema__(:fields)
      assert fields == [:__typename]
    end
  end

  describe "generate_fragment/4" do
    test "generates the fragment module without a plugin list" do
      schema = SchemaHelper.build_schema()
      fragment = parse!("fragment UserFields on User { name email }")

      assert TypedGql.Test.FragmentNoPlugins.Fragments.UserFields ==
               TypeGenerator.generate_fragment(
                 fragment,
                 schema,
                 TypedGql.Test.FragmentNoPlugins,
                 %{}
               )

      fields = TypedGql.Test.FragmentNoPlugins.Fragments.UserFields.__schema__(:fields)
      assert :name in fields
      assert :email in fields
    end
  end

  # Helpers

  defp resolved_tree(schema, query, client_module) do
    TypeGenerator.generate(parse!(query), schema,
      client_module: client_module,
      function_name: :search,
      generation_plugins: [CaptureTreePlugin]
    )

    assert_received {:resolved_tree, tree}
    tree
  end

  # The `search` field's union node holds one object node per member.
  defp variant_field(tree, type_name, field_name) do
    [union_node] = tree.children
    variant = Enum.find(union_node.children, &(&1.parent_type == type_name))
    Enum.find(variant.fields, &(&1.name == field_name))
  end

  defp parse_document!(query) do
    {:ok, document} = TypedGql.Parser.parse(query)
    document
  end

  defp parse!(query) do
    {:ok, %{definitions: [operation | _rest]}} = TypedGql.Parser.parse(query)
    operation
  end

  defp types_with_non_null_name do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "name" => %SchemaField{
            name: "name",
            type: %TypeRef{
              kind: :non_null,
              of_type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      }
    })
  end

  defp types_with_posts do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "name" => %SchemaField{
            name: "name",
            type: %TypeRef{kind: :scalar, name: "String"}
          },
          "posts" => %SchemaField{
            name: "posts",
            type: %TypeRef{
              kind: :non_null,
              of_type: %TypeRef{kind: :object, name: "Post"}
            }
          }
        }
      },
      "Post" => %Type{
        kind: :object,
        name: "Post",
        fields: %{
          "title" => %SchemaField{
            name: "title",
            type: %TypeRef{kind: :scalar, name: "String"}
          }
        }
      }
    })
  end

  defp types_with_list_posts do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "name" => %SchemaField{
            name: "name",
            type: %TypeRef{kind: :scalar, name: "String"}
          },
          "posts" => %SchemaField{
            name: "posts",
            type: %TypeRef{
              kind: :non_null,
              of_type: %TypeRef{
                kind: :list,
                of_type: %TypeRef{kind: :object, name: "Post"}
              }
            }
          }
        }
      },
      "Post" => %Type{
        kind: :object,
        name: "Post",
        fields: %{
          "title" => %SchemaField{
            name: "title",
            type: %TypeRef{kind: :scalar, name: "String"}
          }
        }
      }
    })
  end

  defp types_with_author do
    base = types_with_list_posts()

    put_in(base["Post"], %Type{
      kind: :object,
      name: "Post",
      fields: %{
        "title" => %SchemaField{
          name: "title",
          type: %TypeRef{kind: :scalar, name: "String"}
        },
        "author" => %SchemaField{
          name: "author",
          type: %TypeRef{
            kind: :non_null,
            of_type: %TypeRef{kind: :object, name: "User"}
          }
        }
      }
    })
  end

  defp schema_with_union do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "search" => %SchemaField{
              name: "search",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{
                  kind: :list,
                  of_type: %TypeRef{kind: :union, name: "SearchResult"}
                }
              }
            }
          }
        },
        "SearchResult" => %Type{
          kind: :union,
          name: "SearchResult",
          possible_types: ["User", "Post"]
        },
        "User" => %Type{
          kind: :object,
          name: "User",
          fields: %{
            "__typename" => %SchemaField{
              name: "__typename",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
            },
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "email" => %SchemaField{
              name: "email",
              type: %TypeRef{kind: :scalar, name: "String"}
            },
            "name" => %SchemaField{
              name: "name",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        },
        "Post" => %Type{
          kind: :object,
          name: "Post",
          fields: %{
            "__typename" => %SchemaField{
              name: "__typename",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
            },
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "title" => %SchemaField{
              name: "title",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  # A union whose members implement two interfaces, so one field can be reached
  # through either condition.
  defp schema_with_two_interfaces do
    profile = %SchemaField{name: "profile", type: %TypeRef{kind: :object, name: "Profile"}}
    base = schema_with_union().types

    types =
      base
      |> Map.update!("User", &%{&1 | fields: Map.put(&1.fields, "profile", profile)})
      |> Map.update!("Post", &%{&1 | fields: Map.put(&1.fields, "profile", profile)})
      |> Map.put("Node", %Type{
        kind: :interface,
        name: "Node",
        possible_types: ["User", "Post"],
        fields: %{
          "id" => %SchemaField{
            name: "id",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
          },
          "profile" => %SchemaField{
            name: "profile",
            type: %TypeRef{kind: :object, name: "Profile"}
          }
        }
      })
      |> Map.put("Named", %Type{
        kind: :interface,
        name: "Named",
        possible_types: ["User"],
        fields: %{
          "id" => %SchemaField{
            name: "id",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
          },
          "name" => %SchemaField{name: "name", type: %TypeRef{kind: :scalar, name: "String"}},
          "profile" => %SchemaField{
            name: "profile",
            type: %TypeRef{kind: :object, name: "Profile"}
          }
        }
      })
      |> Map.put("Profile", %Type{
        kind: :object,
        name: "Profile",
        fields: %{
          "bio" => %SchemaField{name: "bio", type: %TypeRef{kind: :scalar, name: "String"}},
          "avatar" => %SchemaField{name: "avatar", type: %TypeRef{kind: :scalar, name: "String"}}
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  # Content implements Named, but Named covers only one of Content's members, so
  # its fields cannot be shared with the other.
  # A real introspection result lists __Schema and __Type among its types.
  defp schema_with_introspection do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "__Schema" => %Type{
          kind: :object,
          name: "__Schema",
          fields: %{
            "queryType" => %SchemaField{
              name: "queryType",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :object, name: "__Type"}}
            }
          }
        },
        "__Type" => %Type{
          kind: :object,
          name: "__Type",
          fields: %{
            "name" => %SchemaField{name: "name", type: %TypeRef{kind: :scalar, name: "String"}}
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  # Node.friend returns Node, but User.friend narrows it to User.
  defp schema_covariant_interface do
    friend = fn type_name ->
      %SchemaField{name: "friend", type: %TypeRef{kind: :object, name: type_name}}
    end

    SchemaHelper.build_schema(
      types: %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "search" => %SchemaField{
              name: "search",
              type: %TypeRef{kind: :union, name: "Search"},
              args: %{}
            }
          }
        },
        "Search" => %Type{kind: :union, name: "Search", possible_types: ["User", "Post"]},
        "Node" => %Type{
          kind: :interface,
          name: "Node",
          possible_types: ["User", "Post"],
          fields: %{"friend" => friend.("Node")}
        },
        "User" => %Type{
          kind: :object,
          name: "User",
          interfaces: ["Node"],
          fields: %{
            "friend" => friend.("User"),
            "email" => %SchemaField{name: "email", type: %TypeRef{kind: :scalar, name: "String"}}
          }
        },
        "Post" => %Type{
          kind: :object,
          name: "Post",
          interfaces: ["Node"],
          fields: %{"friend" => friend.("Node")}
        },
        "String" => %Type{kind: :scalar, name: "String"}
      }
    )
  end

  defp schema_partial_interface do
    types =
      schema_with_union().types
      |> Map.put("Query", %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "search" => %SchemaField{
            name: "search",
            type: %TypeRef{kind: :list, of_type: %TypeRef{kind: :interface, name: "Content"}},
            args: %{}
          }
        }
      })
      |> Map.put("Content", %Type{
        kind: :interface,
        name: "Content",
        interfaces: ["Named"],
        possible_types: ["User", "Post"],
        fields: %{
          "name" => %SchemaField{name: "name", type: %TypeRef{kind: :scalar, name: "String"}}
        }
      })
      |> Map.put("Named", %Type{
        kind: :interface,
        name: "Named",
        possible_types: ["User"],
        fields: %{
          "name" => %SchemaField{name: "name", type: %TypeRef{kind: :scalar, name: "String"}}
        }
      })
      |> Map.update!("User", fn type ->
        %{
          type
          | fields:
              Map.put(type.fields, "name", %SchemaField{
                name: "name",
                type: %TypeRef{kind: :scalar, name: "String"}
              })
        }
      end)

    SchemaHelper.build_schema(types: types)
  end

  # Parent implements Mid, Mid implements Base: a `... on Base` fragment under a
  # Parent still selects fields Parent declares.
  defp schema_transitive_interfaces do
    id_field = %SchemaField{
      name: "id",
      type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
    }

    interface = fn name, interfaces ->
      %Type{
        kind: :interface,
        name: name,
        interfaces: interfaces,
        possible_types: ["User"],
        fields: %{"id" => id_field}
      }
    end

    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "node" => %SchemaField{
              name: "node",
              type: %TypeRef{kind: :interface, name: "Parent"},
              args: %{}
            }
          }
        },
        "Base" => interface.("Base", []),
        "Mid" => interface.("Mid", ["Base"]),
        "Parent" => interface.("Parent", ["Mid"])
      })

    SchemaHelper.build_schema(types: types)
  end

  # Timestamped implements Node, so a `... on Node` fragment under a Timestamped
  # parent selects fields Timestamped itself declares.
  defp schema_interface_implementing_interface do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "node" => %SchemaField{
              name: "node",
              type: %TypeRef{kind: :interface, name: "Timestamped"},
              args: %{}
            }
          }
        },
        "Node" => %Type{
          kind: :interface,
          name: "Node",
          possible_types: ["User"],
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            }
          }
        },
        "Timestamped" => %Type{
          kind: :interface,
          name: "Timestamped",
          interfaces: ["Node"],
          possible_types: ["User"],
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  defp schema_with_union_of_nodes do
    types =
      Map.put(schema_with_union().types, "Node", %Type{
        kind: :interface,
        name: "Node",
        possible_types: ["User", "Post"],
        fields: %{
          "id" => %SchemaField{
            name: "id",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  defp schema_with_single_union do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "node" => %SchemaField{
              name: "node",
              type: %TypeRef{kind: :union, name: "Node"}
            }
          }
        },
        "Node" => %Type{
          kind: :union,
          name: "Node",
          possible_types: ["User", "Post"]
        },
        "User" => %Type{
          kind: :object,
          name: "User",
          fields: %{
            "__typename" => %SchemaField{
              name: "__typename",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
            },
            "name" => %SchemaField{
              name: "name",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        },
        "Post" => %Type{
          kind: :object,
          name: "Post",
          fields: %{
            "__typename" => %SchemaField{
              name: "__typename",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
            },
            "title" => %SchemaField{
              name: "title",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  # Interface type where concrete types do NOT have __typename in their fields,
  # matching real introspection JSON behaviour.
  defp schema_with_interface_no_typename do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "node" => %SchemaField{
              name: "node",
              type: %TypeRef{kind: :interface, name: "Node"},
              args: %{
                "id" => %TypedGql.Schema.InputValue{
                  name: "id",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :scalar, name: "ID"}
                  }
                }
              }
            }
          }
        },
        "Node" => %Type{
          kind: :interface,
          name: "Node",
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            }
          },
          possible_types: ["AppSubscription", "Shop"]
        },
        "AppSubscription" => %Type{
          kind: :object,
          name: "AppSubscription",
          interfaces: ["Node"],
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "status" => %SchemaField{
              name: "status",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        },
        "Shop" => %Type{
          kind: :object,
          name: "Shop",
          interfaces: ["Node"],
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "name" => %SchemaField{
              name: "name",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  # Object parent (User) whose selection uses an inline fragment on an
  # interface it implements. Exercises the object-mode flattening path where a
  # nested inline fragment must not leak into resolve_object/5.
  defp schema_object_with_interface do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "user" => %SchemaField{
              name: "user",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :object, name: "User"}}
            }
          }
        },
        "Node" => %Type{
          kind: :interface,
          name: "Node",
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            }
          },
          possible_types: ["User"]
        },
        "User" => %Type{
          kind: :object,
          name: "User",
          interfaces: ["Node"],
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "name" => %SchemaField{
              name: "name",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end
end
