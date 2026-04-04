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
      Given a module that calls use Grephql with otp_app, source, type_style :struct, and scalars mapping
      When the module is compiled
      Then compile-time options (type_style, scalars) are used for type generation

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

    Scenario: type_style is a compile-time option
      Given a client module configured with type_style :struct
      Then the type_style is applied during compilation and cannot be changed at runtime

    Scenario: endpoint is a runtime option
      Given runtime config sets endpoint to "https://api.example.com/graphql"
      Then the endpoint is resolved at runtime when queries are executed
