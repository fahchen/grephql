@compile-time
Feature: Compile-time GraphQL validation
  As an Elixir developer
  I want my GraphQL operations validated against the schema at compile time
  So that I catch query errors before runtime

  # --- Schema Loading ---

  Rule: Schema is loaded at compile time from the configured source

    Scenario: Schema loaded from a local file
      Given a client module configured with source "priv/schemas/service.json"
      And the file contains a valid introspection JSON with a "user" type
      When the module is compiled
      Then the schema is available for validation

    Scenario: Schema loaded from an inline string
      Given a client module configured with an inline introspection JSON source
      When the module is compiled
      Then the schema is available for validation

    Scenario: Schema fetch failure blocks compilation
      Given a client module configured with source "priv/schemas/missing.json"
      And the file does not exist
      When the module is compiled
      Then a compile error is raised indicating the schema could not be loaded

  # --- Operation Structure ---

  Rule: Operations must reference existing root types

    Scenario: Query operation with valid query root type
      Given a schema with a query root type "Query" having field "user"
      When the developer writes ~GQL with "query { user { name } }"
      Then the module compiles successfully

    Scenario: Mutation operation without mutation root type raises compile error
      Given a schema with no mutation root type defined
      When the developer writes ~GQL with "mutation { createUser { id } }"
      Then a compile error is raised indicating mutation is not supported by the schema

  Rule: Anonymous operations must be singular

    Scenario: Single anonymous operation compiles
      Given a ~GQL with one anonymous query "{ user { name } }"
      When the module is compiled
      Then the module compiles successfully

    Scenario: Multiple anonymous operations raise compile error
      Given a ~GQL with two anonymous queries
      When the module is compiled
      Then a compile error is raised indicating only one anonymous operation is allowed

  Rule: Operation names must be unique

    Scenario: Duplicate operation names raise compile error
      Given a ~GQL with two named operations both called "GetUser"
      When the module is compiled
      Then a compile error is raised indicating duplicate operation name "GetUser"

  # --- Field Validation ---

  Rule: Field references are validated against the schema

    Scenario: Valid field selection compiles successfully
      Given a schema with type "User" having fields "name" and "email"
      When the developer writes ~GQL with "query { user { name email } }"
      Then the module compiles successfully

    Scenario: Invalid field reference raises compile error
      Given a schema with type "User" having fields "name" and "email"
      When the developer writes ~GQL with "query { user { nonExistentField } }"
      Then a compile error is raised indicating "nonExistentField" does not exist on type "User"

  Rule: Scalar fields must not have sub-selections

    Scenario: Sub-selection on scalar raises compile error
      Given a schema where "name" on "User" is of type "String!"
      When the developer writes ~GQL with "query { user { name { length } } }"
      Then a compile error is raised indicating "name" is a scalar and cannot have sub-selections

  Rule: Composite types must have sub-selections

    Scenario: Missing sub-selection on object type raises compile error
      Given a schema where "user" returns type "User" (an object)
      When the developer writes ~GQL with "query { user }"
      Then a compile error is raised indicating "user" is an object type and requires a sub-selection

  Rule: Empty selection sets are invalid

    Scenario: Empty selection set raises compile error
      Given a schema with type "User"
      When the developer writes ~GQL with "query { user { } }"
      Then a compile error is raised indicating empty selection set

  # --- Argument Validation ---

  Rule: Argument names are validated against field definitions

    Scenario: Valid argument compiles
      Given a schema where "user" accepts argument "id" of type "ID!"
      When the developer writes ~GQL with "query { user(id: \"123\") { name } }"
      Then the module compiles successfully

    Scenario: Non-existent argument raises compile error
      Given a schema where "user" accepts only argument "id"
      When the developer writes ~GQL with "query { user(foo: \"bar\") { name } }"
      Then a compile error is raised indicating "foo" is not a valid argument on "user"

  Rule: Required arguments must be provided

    Scenario: Missing required argument raises compile error
      Given a schema where "user" requires argument "id" of type "ID!"
      When the developer writes ~GQL with "query { user { name } }"
      Then a compile error is raised indicating required argument "id" is missing on "user"

  Rule: Argument types must match

    Scenario: Argument type mismatch raises compile error
      Given a schema where "user" accepts argument "id" of type "ID!"
      When the developer writes ~GQL with "query { user(id: 123) { name } }"
      Then a compile error is raised indicating type mismatch for argument "id"

  Rule: Arguments must be unique per field

    Scenario: Duplicate argument raises compile error
      Given a schema where "user" accepts argument "id"
      When the developer writes ~GQL with "query { user(id: \"1\", id: \"2\") { name } }"
      Then a compile error is raised indicating duplicate argument "id" on "user"

  # --- Variable Validation ---

  Rule: Variable types are validated against argument types

    Scenario: Matching variable and argument types compile successfully
      Given a schema where "user" accepts argument "id" of type "ID!"
      When the developer writes ~GQL with "query($id: ID!) { user(id: $id) { name } }"
      Then the module compiles successfully

    Scenario: Mismatched variable type raises compile error
      Given a schema where "user" accepts argument "id" of type "ID!"
      When the developer writes ~GQL with "query($id: String!) { user(id: $id) { name } }"
      Then a compile error is raised indicating type mismatch between "String!" and "ID!"

  Rule: All defined variables must be used

    Scenario: Unused variable raises compile error
      Given a ~GQL with "query($id: ID!, $name: String!) { user(id: $id) { name } }"
      When the module is compiled
      Then a compile error is raised indicating variable "$name" is defined but not used

  Rule: All used variables must be defined

    Scenario: Undefined variable raises compile error
      Given a ~GQL with "query($id: ID!) { user(id: $id) { posts(limit: $limit) { title } } }"
      When the module is compiled
      Then a compile error is raised indicating variable "$limit" is used but not defined

  Rule: Variable names must be unique

    Scenario: Duplicate variable definition raises compile error
      Given a ~GQL with "query($id: ID!, $id: String!) { user(id: $id) { name } }"
      When the module is compiled
      Then a compile error is raised indicating duplicate variable "$id"

  # --- Directive Validation ---

  Rule: Directives must exist in the schema

    Scenario: Unknown directive raises compile error
      Given a schema with directives "skip" and "include"
      When the developer writes ~GQL with "query { user @foo { name } }"
      Then a compile error is raised indicating directive "@foo" is not defined

  Rule: Directives must be used in valid locations

    Scenario: Directive in wrong location raises compile error
      Given a schema where "@skip" is allowed on FIELD, FRAGMENT_SPREAD, INLINE_FRAGMENT
      When the developer writes ~GQL with "query @skip(if: true) { user { name } }"
      Then a compile error is raised indicating "@skip" is not allowed on QUERY

  Rule: Directive arguments are validated

    Scenario: Missing required directive argument raises compile error
      Given a schema where "@skip" requires argument "if" of type "Boolean!"
      When the developer writes ~GQL with "query { user @skip { name } }"
      Then a compile error is raised indicating required argument "if" is missing on "@skip"

    Scenario: Wrong directive argument type raises compile error
      Given a schema where "@skip" requires argument "if" of type "Boolean!"
      When the developer writes ~GQL with "query { user @skip(if: \"yes\") { name } }"
      Then a compile error is raised indicating type mismatch for argument "if" on "@skip"

  Rule: Non-repeatable directives must not be duplicated

    Scenario: Repeated non-repeatable directive raises compile error
      Given a schema where "@skip" is non-repeatable
      When the developer writes ~GQL with "query { user @skip(if: true) @skip(if: false) { name } }"
      Then a compile error is raised indicating "@skip" cannot be repeated

  # --- Inline Fragment Validation ---

  Rule: Type conditions must reference valid types in context

    Scenario: Valid inline fragment on union member compiles
      Given a schema union "SearchResult" of types "User" and "Post"
      When the developer writes ~GQL with "query { search { ... on User { name } ... on Post { title } } }"
      Then the module compiles successfully

    Scenario: Invalid type condition raises compile error
      Given a schema union "SearchResult" of types "User" and "Post"
      When the developer writes ~GQL with "query { search { ... on Comment { body } } }"
      Then a compile error is raised indicating "Comment" is not a member of union "SearchResult"

  # --- Input Object Validation (inline literals only — variable contents are runtime) ---

  Rule: Inline input object fields must exist in the input type definition

    Scenario: Non-existent field in inline input literal raises compile error
      Given a schema input "CreateUserInput" with fields "name" and "email"
      When the developer writes ~GQL with "mutation { createUser(input: {name: \"Alice\", phone: \"123\"}) { id } }"
      Then a compile error is raised indicating "phone" does not exist on input "CreateUserInput"

    Scenario: Valid inline input literal compiles
      Given a schema input "CreateUserInput" with fields "name" and "email"
      When the developer writes ~GQL with "mutation { createUser(input: {name: \"Alice\"}) { id } }"
      Then the module compiles successfully

  Rule: Required fields in inline input literals must be provided

    Scenario: Missing required field in inline input literal raises compile error
      Given a schema input "CreateUserInput" with required field "name: String!" and optional field "email: String"
      When the developer writes ~GQL with "mutation { createUser(input: {email: \"a@b.com\"}) { id } }"
      Then a compile error is raised indicating required field "name" is missing on "CreateUserInput"

  Rule: Inline input object fields must be unique

    Scenario: Duplicate field in inline input literal raises compile error
      Given a schema input "CreateUserInput"
      When the developer writes ~GQL with "mutation { createUser(input: {name: \"Alice\", name: \"Bob\"}) { id } }"
      Then a compile error is raised indicating duplicate field "name" on "CreateUserInput"

  Rule: Enum values must be valid members

    Scenario: Valid enum value compiles
      Given a schema enum "Role" with values "ADMIN" and "USER"
      When the developer writes ~GQL with a variable or literal using "ADMIN"
      Then the module compiles successfully

    Scenario: Invalid enum value raises compile error
      Given a schema enum "Role" with values "ADMIN" and "USER"
      When the developer writes ~GQL with a literal enum value "SUPERADMIN"
      Then a compile error is raised indicating "SUPERADMIN" is not a valid value for enum "Role"

  # --- Custom Scalar Validation ---

  Rule: Custom scalars must have a configured Ecto Type mapping or built-in

    Scenario: Custom scalar with Ecto Type module compiles successfully
      Given a schema with custom scalar "DateTime"
      And the client module is configured with scalars %{"DateTime" => MyApp.Types.DateTime}
      And MyApp.Types.DateTime implements Ecto.Type
      When the developer writes ~GQL referencing a "DateTime" field
      Then the module compiles successfully

    Scenario: Built-in Ecto Type scalar compiles without explicit mapping
      Given a schema with custom scalar "DateTime"
      And Grephql provides a built-in Ecto Type for "DateTime"
      And no explicit scalar mapping is configured
      When the developer writes ~GQL referencing a "DateTime" field
      Then the module compiles successfully using the built-in

    Scenario: Unknown custom scalar without mapping or built-in raises compile error
      Given a schema with custom scalar "CustomFoo"
      And no scalar mapping is configured for "CustomFoo"
      And no built-in Ecto Type exists for "CustomFoo"
      When the developer writes ~GQL referencing a "CustomFoo" field
      Then a compile error is raised indicating "CustomFoo" has no configured mapping

  # --- Deprecation Warnings ---

  Rule: Deprecated fields produce compile warnings

    Scenario: Using a deprecated field emits a compile warning
      Given a schema where field "oldEmail" on type "User" is deprecated with reason "use email instead"
      When the developer writes ~GQL with "query { user { oldEmail } }"
      Then a compile warning is emitted indicating "oldEmail" on "User" is deprecated with reason "use email instead"
      And the module compiles successfully

    Scenario: Non-deprecated fields produce no warning
      Given a schema where field "email" on type "User" is not deprecated
      When the developer writes ~GQL with "query { user { email } }"
      Then no deprecation warning is emitted

  Rule: Deprecated enum values produce compile warnings

    Scenario: Using a deprecated enum value emits a compile warning
      Given a schema enum "Status" where value "LEGACY" is deprecated with reason "use INACTIVE"
      When the developer writes ~GQL with a literal enum value "LEGACY"
      Then a compile warning is emitted indicating "LEGACY" on "Status" is deprecated with reason "use INACTIVE"
      And the module compiles successfully
