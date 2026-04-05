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

  Rule: Schema parse result is cached by content hash

    Scenario: Unchanged schema source skips re-parsing
      Given a client module with source "priv/schemas/service.json"
      And the schema file has not changed since last compilation
      When the module is recompiled
      Then the schema is loaded from cache without re-parsing the JSON

    Scenario: Changed schema source invalidates cache
      Given a client module with source "priv/schemas/service.json"
      And the schema file content has changed since last compilation
      When the module is recompiled
      Then the schema is re-parsed from the updated file

  Rule: Each GQL compilation result is cached by schema hash + query content hash

    Scenario: Unchanged query with unchanged schema skips recompilation
      Given a defgql :get_user with a specific query string
      And neither the schema source nor the query string has changed
      When the module is recompiled
      Then the query validation and type generation are skipped
      And the previously generated structs and function are reused

    Scenario: Changed query content invalidates query cache
      Given a defgql :get_user with a modified query string
      And the schema source has not changed
      When the module is recompiled
      Then the query is re-validated and types are re-generated

    Scenario: Changed schema invalidates all query caches for that schema
      Given a client module with multiple defgql definitions
      And the schema source has changed
      When the module is recompiled
      Then all queries are re-validated and types are re-generated
