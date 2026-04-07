@client-module
Feature: Client module configuration
  As an Elixir developer
  I want to configure a GraphQL client module with use Grephql
  So that I can bind a schema source and settings in one place

  Rule: Client module is defined with use Grephql and otp_app

    Scenario: Minimal client module with file source
      Given a module that calls use Grephql with otp_app: :my_app and source: "priv/schemas/service.json"
      When the module is compiled
      Then the module is configured to load the schema from the specified file
      And runtime config is read from config :my_app, MyModule

    Scenario: Client module with all compile-time options
      Given a module that calls use Grephql with otp_app, source, and scalars mapping
      When the module is compiled
      Then compile-time options (scalars) are used for type generation

  Rule: Multiple client modules support multiple schemas

    Scenario: Two client modules for different services
      Given MyApp.UserService uses Grephql with source "priv/schemas/user.json"
      And MyApp.OrderService uses Grephql with source "priv/schemas/order.json"
      When both modules are compiled
      Then each module validates queries against its own schema independently

  Rule: Config priority is execute opts > runtime config > use options > defaults

    Scenario: Runtime config overrides use options for endpoint
      Given a client module with no endpoint in use options
      And runtime config sets endpoint to "https://api.example.com/graphql"
      When a query is executed
      Then the runtime config endpoint is used

    Scenario: Execute opts override runtime config
      Given runtime config sets endpoint to "https://api.example.com/graphql"
      When a query is executed with opts endpoint: "https://staging.example.com/graphql"
      Then the staging endpoint is used

  Rule: Compile-time config stays in use options, runtime config stays in otp_app config

    Scenario: scalars mapping is a compile-time option
      Given a client module configured with scalars %{"DateTime" => MyApp.Types.DateTime}
      Then the scalars mapping is applied during compilation and cannot be changed at runtime

    Scenario: endpoint is a runtime option
      Given runtime config sets endpoint to "https://api.example.com/graphql"
      Then the endpoint is resolved at runtime when queries are executed

  Rule: Req options are passed through to the HTTP client

    Scenario: Compile-time req_options are used as defaults
      Given a client module configured with req_options: [receive_timeout: 30_000]
      When a query is executed without per-call opts
      Then Req uses the compile-time receive_timeout

    Scenario: Runtime config req_options override compile-time defaults
      Given a client module configured with req_options: [receive_timeout: 30_000]
      And runtime config sets req_options: [receive_timeout: 60_000]
      When a query is executed
      Then Req uses the runtime config receive_timeout

    Scenario: Per-call req_options override runtime config
      Given runtime config sets req_options: [receive_timeout: 30_000]
      When a query is executed with req_options: [receive_timeout: 5_000]
      Then Req uses the per-call receive_timeout

    Scenario: Req.Test plug is supported for testing
      Given runtime config sets req_options: [plug: {Req.Test, MyApp.GitHub}]
      When a query is executed
      Then Req routes the request through the test plug instead of making a real HTTP call
