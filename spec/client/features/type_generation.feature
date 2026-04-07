@type-generation
Feature: GraphQL to Elixir type generation
  As an Elixir developer
  I want GraphQL types mapped to Elixir embedded schemas automatically
  So that I get type safety without manually defining structs and typespecs

  Rule: Output types are generated as embedded schemas using EctoTypedSchema

    Scenario: Generated output type uses EctoTypedSchema embedded schema
      Given a client module MyApp.UserService
      And a schema with type "User" having fields "name: String!" and "email: String"
      When the developer defines defgql :get_user with "query { user { name email } }"
      Then the generated MyApp.UserService.GetUser.User is an embedded schema
      And non-null fields are enforced, nullable fields default to nil
      And automatic @type t() spec is generated

  Rule: Output struct names are derived from the query field path under a Result namespace (per-query isolation)

    Scenario: Top-level field becomes ClientModule.FunctionName.Result.FieldName
      Given a client module MyApp.UserService
      When the developer defines defgql :get_user with "query($id: ID!) { user(id: $id) { name email } }"
      Then the generated struct is MyApp.UserService.GetUser.Result.User

    Scenario: Nested fields extend the path
      Given a client module MyApp.UserService
      When the developer defines defgql :get_user with "query($id: ID!) { user(id: $id) { name posts { title author { name } } } }"
      Then the generated structs are:
        | struct name                                                 |
        | MyApp.UserService.GetUser.Result.User                       |
        | MyApp.UserService.GetUser.Result.User.Posts                 |
        | MyApp.UserService.GetUser.Result.User.Posts.Author          |

    Scenario: Field aliases use the alias name for struct field and module path
      Given a client module MyApp.UserService
      When the developer defines defgql :get_user with "query($id: ID!) { author: user(id: $id) { name } }"
      Then the generated struct is MyApp.UserService.GetUser.Result.Author
      And the struct field is :author (snake_cased from the alias)

    Scenario: Different queries for same type get independent structs
      Given a client module MyApp.UserService
      And defgql :get_user selects "name email" on User
      And defgql :list_users selects only "name" on User
      Then MyApp.UserService.GetUser.Result.User has fields name and email
      And MyApp.UserService.ListUsers.Result.User has only field name

  Rule: Nested object types are also embedded schemas (fully recursive)

    Scenario: All nesting levels are embedded schemas
      Given a client module MyApp.UserService
      And a query selecting user { name posts { title author { name } } }
      When the types are generated
      Then user, posts, and author are all embedded schemas
      And the result is %User{name: "Alice", posts: [%Posts{title: "Hello", author: %Author{name: "Bob"}}]}

  Rule: Response JSON is deserialized into embedded schemas via Ecto.Changeset

    Scenario: Successful response is cast into typed structs
      Given a defgql :get_user returning type MyApp.UserService.GetUser.User
      When the GraphQL server returns {"data": {"user": {"name": "Alice", "email": "a@b.com"}}}
      Then the response data is cast via Ecto.Changeset into %MyApp.UserService.GetUser.User{name: "Alice", email: "a@b.com"}

    Scenario: Nested response is recursively cast
      Given a defgql :get_user with nested selection "user { name posts { title } }"
      When the server returns nested JSON data
      Then all nesting levels are cast into their respective embedded schema structs

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

  Rule: GraphQL unions and interfaces map to direct struct union

    Scenario: Union type uses struct matching
      Given a schema union "SearchResult" of types "User" and "Post"
      When the type is generated
      Then the Elixir type is User.t() | Post.t()
      And pattern matching uses %User{} or %Post{}

  Rule: Input types are generated as schema-level embedded schemas with build/1

    Scenario: Input type generates embedded schema struct
      Given a client module MyApp.UserService
      And a schema input "CreateUserInput" with fields "name: String!" and "email: String"
      When the type is generated
      Then an embedded schema MyApp.UserService.Inputs.CreateUserInput is generated with the corresponding fields

    Scenario: Input type provides build/1 to construct from plain map
      Given a generated input type MyApp.UserService.CreateUserInput
      When the developer calls MyApp.UserService.Inputs.CreateUserInput.build(%{name: "Alice", email: "a@b.com"})
      Then it returns {:ok, %MyApp.UserService.Inputs.CreateUserInput{name: "Alice", email: "a@b.com"}}

    Scenario: build/1 validates required fields via changeset
      Given a generated input type MyApp.UserService.Inputs.CreateUserInput with required field "name: String!"
      When the developer calls MyApp.UserService.Inputs.CreateUserInput.build(%{email: "a@b.com"})
      Then it returns {:error, changeset} with validation error for missing "name"

  Rule: Input type structs are named under ClientModule.Inputs namespace

    Scenario: Input type struct is shared across queries
      Given a client module MyApp.UserService
      And a schema input "CreateUserInput" used by multiple mutations
      Then only one struct MyApp.UserService.Inputs.CreateUserInput is generated
      And it is reusable across all queries that reference CreateUserInput

    Scenario: Input type naming differs from output type naming
      Given a client module MyApp.UserService
      And defgql :create_user with "mutation($input: CreateUserInput!) { createUser(input: $input) { id name } }"
      Then the input struct is MyApp.UserService.Inputs.CreateUserInput (under Inputs namespace)
      And the output struct is MyApp.UserService.CreateUser.Result.CreateUser (under Result namespace)

  Rule: Custom scalar types use Ecto Type for casting, serialization, and deserialization

    Scenario: Custom scalar via Ecto Type module
      Given a schema field "createdAt: DateTime!"
      And the scalar mapping includes "DateTime" => MyApp.Types.DateTime
      And MyApp.Types.DateTime implements the Ecto.Type behaviour (type/0, cast/1, dump/1, load/1)
      When the type is generated
      Then the Elixir type is derived from the Ecto Type's type/0 callback
      And values are serialized via dump/1 and deserialized via load/1

    Scenario: Built-in Ecto Type scalar provided by Grephql
      Given a schema field "createdAt: DateTime!"
      And no custom scalar mapping is configured for "DateTime"
      But Grephql provides a built-in Grephql.Types.DateTime implementing Ecto.Type
      When the type is generated
      Then the built-in type is used automatically

  Rule: GraphQL enums use Ecto.Type for serialization and deserialization

    Scenario: Enum values are cast and serialized via Ecto Type
      Given a schema enum "Status" with values "ACTIVE" and "INACTIVE"
      When an enum value is serialized for a request
      Then the atom :active is dumped as the string "ACTIVE"
      And the string "ACTIVE" from a response is loaded as the atom :active
