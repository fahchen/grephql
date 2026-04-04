@mix-tasks
Feature: Mix tasks
  As an Elixir developer
  I want mix tasks to manage GraphQL schemas
  So that I can fetch and update schemas from remote endpoints

  Rule: mix grephql.download_schema fetches introspection schema from a remote endpoint

    Scenario: Download schema to a file
      Given a GraphQL endpoint at "https://api.example.com/graphql"
      When the developer runs mix grephql.download_schema --endpoint "https://api.example.com/graphql" --output "priv/schemas/service.json"
      Then the introspection query is sent to the endpoint
      And the response is saved to "priv/schemas/service.json"

    Scenario: Download schema with custom headers
      Given a GraphQL endpoint requiring authentication
      When the developer runs mix grephql.download_schema --endpoint "https://api.example.com/graphql" --output "priv/schemas/service.json" --header "Authorization: Bearer token123"
      Then the request includes the authorization header
      And the schema is downloaded successfully

    Scenario: Download fails with clear error message
      Given a GraphQL endpoint that is unreachable
      When the developer runs mix grephql.download_schema --endpoint "https://unreachable.example.com/graphql" --output "priv/schemas/service.json"
      Then a clear error message is displayed indicating the endpoint is unreachable
