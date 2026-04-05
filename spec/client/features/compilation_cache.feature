@compilation-cache
Feature: Compilation caching
  As an Elixir developer
  I want unchanged schemas and queries to be cached between compilations
  So that recompilation is fast when nothing has changed

  Rule: Only types referenced by defgql/defgqlp are generated (on-demand)

    Scenario: Unreferenced schema types are not generated
      Given a schema with types "User", "Post", "Comment", and "Admin"
      And the client module only defines defgql :get_user referencing "User"
      When the module is compiled
      Then only structs for "User" and its selected fields are generated
      And no structs are generated for "Post", "Comment", or "Admin"

  Rule: Schema parse result is cached in persistent_term by source path

    Scenario: Unchanged schema source skips re-parsing within the same BEAM session
      Given a client module with source "priv/schemas/service.json"
      And the schema has already been loaded in this BEAM session
      When another module references the same schema source
      Then the schema is loaded from persistent_term without re-parsing the JSON

  Rule: Schema file changes trigger recompilation via @external_resource

    Scenario: Changed schema file triggers recompilation
      Given a client module with source "priv/schemas/service.json"
      And the schema file is registered as @external_resource
      When the schema file content changes
      Then the Elixir compiler detects the change and recompiles the client module

  Rule: Input type modules are deduplicated across queries

    Scenario: Shared input type is not regenerated
      Given a client module with multiple defgql definitions referencing "CreateUserInput"
      When the module is compiled
      Then only one Inputs.CreateUserInput module is created (via Code.ensure_loaded? guard)
