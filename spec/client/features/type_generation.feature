@type-generation
Feature: GraphQL to Elixir type generation
  As an Elixir developer
  I want GraphQL types mapped to Elixir types automatically
  So that I get type safety without manually defining structs and typespecs

  Rule: Type generation style is configurable via use options

    Scenario: Struct type style generates nested structs
      Given a client module MyApp.UserService configured with type_style :struct
      And a schema with type "User" having fields "name: String!" and "posts: [Post!]!"
      When the developer defines defgql :get_user with "query { user { name posts { title } } }"
      Then the result type includes nested structs named by field path
      And the structs are MyApp.UserService.GetUser.User and MyApp.UserService.GetUser.User.Posts

    Scenario: Map type style generates typed maps
      Given a client module configured with type_style :map
      And a schema with type "User" having fields "name: String!" and "email: String"
      When the developer writes ~GQL with "query { user { name email } }"
      Then the result type is a map with typed keys

    Scenario: Query shape type style generates struct shaped by selected fields
      Given a client module MyApp.UserService configured with type_style :query_shape
      And a schema with type "User" having fields "name: String!", "email: String", and "age: Int"
      When the developer defines defgql :get_user selecting only "name" and "email" on User
      Then the generated struct MyApp.UserService.GetUser.User has only "name" and "email" fields
      And the struct follows field path naming like :struct mode

  Rule: Structs are defined using TypedStructor for automatic typespecs

    Scenario: Generated struct uses TypedStructor DSL
      Given a client module configured with type_style :struct
      And a schema with type "User" having fields "name: String!" and "email: String"
      When the struct is generated
      Then it uses TypedStructor with enforced fields for non-null types and nullable fields for optional types

  Rule: Struct names are derived from the query field path (per-query isolation)

    Scenario: Top-level field becomes ClientModule.FunctionName.FieldName
      Given a client module MyApp.UserService configured with type_style :struct
      When the developer defines defgql :get_user with "query($id: ID!) { user(id: $id) { name email } }"
      Then the generated struct is MyApp.UserService.GetUser.User

    Scenario: Nested fields extend the path
      Given a client module MyApp.UserService configured with type_style :struct
      When the developer defines defgql :get_user with "query($id: ID!) { user(id: $id) { name posts { title author { name } } } }"
      Then the generated structs are:
        | struct name                                          |
        | MyApp.UserService.GetUser.User                       |
        | MyApp.UserService.GetUser.User.Posts                 |
        | MyApp.UserService.GetUser.User.Posts.Author          |

    Scenario: Different queries for same type get independent structs
      Given a client module MyApp.UserService configured with type_style :struct
      And defgql :get_user selects "name email" on User
      And defgql :list_users selects only "name" on User
      Then MyApp.UserService.GetUser.User has fields name and email
      And MyApp.UserService.ListUsers.User has only field name

  Rule: In struct mode nested object types are also structs (fully recursive)

    Scenario: All nesting levels are structs
      Given a client module configured with type_style :struct
      And a query selecting user { name posts { title author { name } } }
      When the types are generated
      Then user, posts, and author are all structs
      And the result is %User{name: "Alice", posts: [%Posts{title: "Hello", author: %Author{name: "Bob"}}]}

  Rule: Nullable GraphQL fields map to type | nil

    Scenario: Non-null field maps to base type
      Given a schema field "name: String!"
      When the type is generated
      Then the Elixir type is String.t()

    Scenario: Nullable field maps to type union with nil
      Given a schema field "name: String"
      When the type is generated
      Then the Elixir type is String.t() | nil

  Rule: List types follow nullable composition

    Scenario Outline: List nullability combinations
      Given a schema field with type <graphql_type>
      When the type is generated
      Then the Elixir type is <elixir_type>

      Examples:
        | graphql_type | elixir_type              |
        | [User!]!     | [User.t()]               |
        | [User!]      | [User.t()] \| nil        |
        | [User]!      | [User.t() \| nil]        |
        | [User]       | [User.t() \| nil] \| nil |

  Rule: GraphQL enums map to downcased Elixir atoms

    Scenario: Enum values become atoms
      Given a schema enum "Status" with values "ACTIVE" and "INACTIVE"
      When the type is generated
      Then the Elixir type is :active | :inactive

  Rule: GraphQL unions and interfaces map to direct type union

    Scenario: Union type in struct mode uses struct matching
      Given a client module configured with type_style :struct
      And a schema union "SearchResult" of types "User" and "Post"
      When the type is generated
      Then the Elixir type is User.t() | Post.t()
      And pattern matching uses %User{} or %Post{}

    Scenario: Union type in map mode uses __typename key
      Given a client module configured with type_style :map
      And a schema union "SearchResult" of types "User" and "Post"
      When the type is generated
      Then the Elixir type is %{__typename: :user, ...} | %{__typename: :post, ...}
      And pattern matching uses %{__typename: :user} or %{__typename: :post}

  Rule: GraphQL input types generate Elixir types controlled by type_style

    Scenario: Input type generates struct when type_style is :struct
      Given a client module MyApp.UserService configured with type_style :struct
      And a schema input "CreateUserInput" with fields "name: String!" and "email: String"
      When the type is generated
      Then a struct MyApp.UserService.CreateUserInput is generated with the corresponding fields

    Scenario: Input type generates typed map when type_style is :map
      Given a client module configured with type_style :map
      And a schema input "CreateUserInput" with fields "name: String!" and "email: String"
      When the type is generated
      Then a typed map is generated with the corresponding keys and types

  Rule: Input type structs are named at schema level (ClientModule.InputTypeName)

    Scenario: Input type struct is shared across queries
      Given a client module MyApp.UserService configured with type_style :struct
      And a schema input "CreateUserInput" used by multiple mutations
      Then only one struct MyApp.UserService.CreateUserInput is generated
      And it is reusable across all queries that reference CreateUserInput

    Scenario: Input type naming differs from output type naming
      Given a client module MyApp.UserService configured with type_style :struct
      And defgql :create_user with "mutation($input: CreateUserInput!) { createUser(input: $input) { id name } }"
      Then the input struct is MyApp.UserService.CreateUserInput (schema-level)
      And the output struct is MyApp.UserService.CreateUser.CreateUser (per-query, field path)

  Rule: Custom scalar types use user-configured mappings with serialize/deserialize

    Scenario: Custom scalar via behaviour module
      Given a schema field "createdAt: DateTime!"
      And the scalar mapping includes "DateTime" => MyApp.Scalars.DateTime
      And MyApp.Scalars.DateTime implements the Grephql.Scalar behaviour
      When the type is generated
      Then the Elixir type is DateTime.t()
      And values are serialized/deserialized using the behaviour callbacks

    Scenario: Custom scalar via shorthand tuple
      Given a schema field "createdAt: DateTime!"
      And the scalar mapping includes "DateTime" => {DateTime, &DateTime.to_iso8601/1, &DateTime.from_iso8601!/1}
      When the type is generated
      Then the Elixir type is DateTime.t()
      And the tuple functions are used for serialization and deserialization

    Scenario: Built-in scalar provided by Grephql
      Given a schema field "createdAt: DateTime!"
      And no custom scalar mapping is configured for "DateTime"
      But Grephql provides a built-in Grephql.Scalar.DateTime
      When the type is generated
      Then the built-in scalar is used automatically
