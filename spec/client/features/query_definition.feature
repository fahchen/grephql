@query-definition
Feature: GraphQL query definition and execution
  As an Elixir developer
  I want to define GraphQL operations declaratively and execute them with typed responses
  So that I can interact with GraphQL APIs safely and concisely

  Rule: defgql generates a public function that directly executes the query

    Scenario: Define and call a query with variables
      Given a client module with a valid schema
      When the developer defines defgql :get_user with "query($id: ID!) { user(id: $id) { name } }"
      Then a public function get_user/2 is generated accepting (variables, opts \\ [])
      And calling get_user(%{id: "123"}) sends the query via Req and returns a typed response

    Scenario: Define and call a query without variables
      Given a client module with a valid schema
      When the developer defines defgql :current_user with "query { currentUser { name email } }"
      Then a public function current_user/1 is generated accepting (opts \\ [])
      And calling current_user() sends the query via Req and returns a typed response

  Rule: defgqlp generates a private function

    Scenario: Private query function is not accessible outside the module
      Given a client module with a valid schema
      When the developer defines defgqlp :internal_lookup with a valid query
      Then a private function internal_lookup is generated
      And the function is not callable from outside the module

  Rule: ~GQL sigil returns a plain string for use with defgql

    Scenario: Use ~GQL heredoc with defgql for formatted queries
      Given a client module with a valid schema
      When the developer defines defgql :create_user with ~GQL heredoc containing a mutation
      Then the query is compiled and a function create_user/2 is generated
      And the ~GQL sigil content can be formatted by mix format

    Scenario: ~GQL formatter plugin auto-formats GraphQL strings
      Given a .formatter.exs with plugins: [Grephql.Formatter] (or import_deps: [:grephql])
      When the developer runs mix format on a file containing a ~GQL heredoc
      Then the GraphQL content inside ~GQL is pretty-printed with proper indentation
      And inline ~GQL sigils (single-line) are left unchanged

  Rule: defgql auto-generates @doc with operation info

    Scenario: Generated function includes @doc
      Given a client module with a valid schema
      When the developer defines defgql :get_user with a query that has variables
      Then the generated function includes @doc with the operation name, variable table, types, and generated module names

  Rule: Grephql.execute takes query, variables, and optional opts (opts defaults to [])

    Scenario: Execute with variables and no options
      Given a defgql function get_user defined with a valid query
      When the developer calls get_user(%{id: "123"})
      Then the query is executed with default options from the runtime config

    Scenario: Execute with empty variables and custom options
      Given a defgql function current_user defined with a no-variable query
      When the developer calls current_user(endpoint: "https://staging.example.com/graphql")
      Then the query is executed against the overridden endpoint

  Rule: Fragments are reused via string interpolation or deffragment

    Scenario: Interpolate a fragment string into a defgql query
      Given a module attribute @user_fields containing "name email"
      When the developer defines defgql :get_user with "query { user { #{@user_fields} } }"
      Then the interpolated query is validated and compiled

    Scenario: Define and use a named fragment via deffragment
      Given a client module with a valid schema
      When the developer defines deffragment :user_fields with a fragment on User
      And defines defgql :get_user with a query that spreads ...UserFields
      Then the fragment is auto-concatenated to the query string
      And the fragment result struct is generated under ClientModule.Fragments.UserFields

    Scenario: Nested fragments are resolved transitively
      Given fragment A spreads fragment B
      And defgql :get_user spreads fragment A
      When the module is compiled
      Then both fragment A and B are concatenated to the query string

  Rule: Response distinguishes GraphQL-level results from transport errors

    Scenario: Successful response with full data
      Given a valid query is executed
      When the GraphQL server returns data with no errors
      Then the response is {:ok, %Grephql.Result{data: typed_result, errors: []}}

    Scenario: Partial data with GraphQL errors
      Given a valid query is executed
      When the GraphQL server returns partial data with field-level errors
      Then the response is {:ok, %Grephql.Result{data: partial_typed_result, errors: [%Grephql.Error{}, ...]}}

    Scenario: Transport-level failure
      Given a valid query is executed
      When the HTTP request fails due to network error
      Then the response is {:error, %Exception{}}

    Scenario: Non-2xx HTTP response
      Given a valid query is executed
      When the GraphQL server returns a non-2xx HTTP status
      Then the response is {:error, %Req.Response{}}

  Rule: GraphQL errors are represented as Grephql.Error structs

    Scenario: Error struct contains standard GraphQL error fields
      Given a GraphQL response with errors
      Then each error is a %Grephql.Error{} with fields message, path, locations, and extensions
      And message is a string
      And path is a list of strings and integers or nil
      And locations is a list of %{line: integer, column: integer} or nil
      And extensions is a map or nil

  Rule: Field aliases map to the alias name in the response struct

    Scenario: Aliased field uses alias as struct field name and module segment
      Given a client module MyApp.UserService
      When the developer defines defgql :get_user with "query($id: ID!) { author: user(id: $id) { name } }"
      Then the result struct has field :author (not :user)
      And the generated module is MyApp.UserService.GetUser.Result.Author (not .User)

  Rule: Endpoint can be overridden at call site

    Scenario: defgql function overrides endpoint via opts
      Given runtime config sets endpoint to "https://api.example.com/graphql"
      When the developer calls get_user(%{id: "123"}, endpoint: "https://staging.example.com/graphql")
      Then the query is sent to the staging endpoint

    Scenario: defgql function overrides endpoint via opts (execute path)
      Given a defgql function get_user defined with a valid query
      When the developer calls get_user(%{id: "123"}, endpoint: "https://staging.example.com/graphql")
      Then the query is sent to the staging endpoint
