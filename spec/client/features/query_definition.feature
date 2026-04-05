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

  Rule: Grephql.execute takes query, variables, and optional opts (opts defaults to [])

    Scenario: Execute with variables and no options
      Given a defgql function get_user defined with a valid query
      When the developer calls get_user(%{id: "123"})
      Then the query is executed with default options from the runtime config

    Scenario: Execute with empty variables and custom options
      Given a defgql function current_user defined with a no-variable query
      When the developer calls current_user(endpoint: "https://staging.example.com/graphql")
      Then the query is executed against the overridden endpoint

  Rule: Fragments are reused via string interpolation in plain strings

    Scenario: Interpolate a fragment string into a defgql query
      Given a module attribute @user_fields containing "name email"
      When the developer defines defgql :get_user with "query { user { #{@user_fields} } }"
      Then the interpolated query is validated and compiled

  Rule: Response distinguishes GraphQL-level results from transport errors

    Scenario: Successful response with full data
      Given a valid query is executed
      When the GraphQL server returns data with no errors
      Then the response is {:ok, %{data: typed_result, errors: []}}

    Scenario: Partial data with GraphQL errors
      Given a valid query is executed
      When the GraphQL server returns partial data with field-level errors
      Then the response is {:ok, %{data: partial_typed_result, errors: [%Grephql.Error{}, ...]}}

    Scenario: Transport-level failure
      Given a valid query is executed
      When the HTTP request fails due to network error
      Then the response is {:error, reason}

  Rule: GraphQL errors are represented as Grephql.Error structs

    Scenario: Error struct contains standard GraphQL error fields
      Given a GraphQL response with errors
      Then each error is a %Grephql.Error{} with fields message, path, locations, and extensions
      And message is a string
      And path is a list of strings and integers or nil
      And locations is a list of %{line: integer, column: integer} or nil
      And extensions is a map or nil

  Rule: Endpoint can be overridden at call site

    Scenario: defgql function overrides endpoint via opts
      Given runtime config sets endpoint to "https://api.example.com/graphql"
      When the developer calls get_user(%{id: "123"}, endpoint: "https://staging.example.com/graphql")
      Then the query is sent to the staging endpoint

    Scenario: defgql function overrides endpoint via opts (execute path)
      Given a defgql function get_user defined with a valid query
      When the developer calls get_user(%{id: "123"}, endpoint: "https://staging.example.com/graphql")
      Then the query is sent to the staging endpoint
