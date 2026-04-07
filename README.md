# Grephql
[![Build Status](https://github.com/fahchen/grephql/actions/workflows/ci.yml/badge.svg)](https://github.com/fahchen/grephql/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/grephql)](https://hex.pm/packages/grephql)
[![HexDocs](https://img.shields.io/badge/HexDocs-gray)](https://hexdocs.pm/grephql)

Compile-time GraphQL client for Elixir. Parses and validates queries during compilation, generates typed Ecto embedded schemas for responses and variables, and executes queries at runtime via [Req](https://github.com/wojtekmach/req).

## Features

- **Compile-time validation** — GraphQL syntax errors and schema mismatches caught at `mix compile`, with line:column positions pointing into your Elixir source
- **Deprecation warnings** — Fields, arguments, enum values, and input fields marked `@deprecated` emit compile-time warnings
- **Typed responses** — Auto-generated Ecto embedded schemas for query results
- **Typed variables** — Input validation via Ecto changesets with generated `params()` type
- **Zero runtime parsing** — All GraphQL parsing happens at compile time
- **Req integration** — Full access to Req's middleware/plugin system, including `Req.Test` for testing
- **Auto-generated docs** — `defgql` functions include `@doc` with variables, types, and generated modules

## Installation

Add `grephql` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:grephql, "~> 0.5.0"}
  ]
end
```

## Quick Start

### 1. Download your schema

```bash
mix grephql.download_schema \
  --endpoint https://api.example.com/graphql \
  --output priv/schemas/schema.json \
  --header "Authorization: Bearer token123"
```

### 2. Define a client module

```elixir
defmodule MyApp.GitHub do
  use Grephql,
    otp_app: :my_app,
    source: "priv/schemas/github.json",
    endpoint: "https://api.github.com/graphql"

  defgql :get_user, ~GQL"""
    query GetUser($login: String!) {
      user(login: $login) {
        name
        bio
      }
    }
  """

  defgql :get_viewer, ~GQL"""
    query {
      viewer {
        login
        email
      }
    }
  """
end
```

### 3. Call the generated functions

```elixir
# With variables — validates input before sending
case MyApp.GitHub.get_user(%{login: "octocat"}) do
  {:ok, result} ->
    result.data.user.name  #=> "The Octocat"

  {:error, %Ecto.Changeset{} = changeset} ->
    # Variable validation failed
    changeset.errors

  {:error, %Req.Response{} = response} ->
    # HTTP error
    response.status
end

# Without variables
{:ok, result} = MyApp.GitHub.get_viewer()
result.data.viewer.login
```

## Macros

### `defgql` / `defgqlp`

Defines a public (or private) GraphQL query function. At compile time: parses, validates, generates typed modules, and defines a callable function.

```elixir
# Public — generates def get_user/2
defgql :get_user, ~GQL"""
  query GetUser($id: ID!) {
    user(id: $id) { name }
  }
"""

# Private — generates defp get_user/2
defgqlp :get_user, ~GQL"""
  query GetUser($id: ID!) {
    user(id: $id) { name }
  }
"""
```

`defgql` functions automatically include `@doc` with operation info, variable table, and all generated module names.

### `deffragment`

Defines a reusable named fragment. Fragments are validated at compile time and automatically appended to queries that reference them via `...FragmentName`.

```elixir
deffragment :user_fields, ~GQL"""
  fragment UserFields on User {
    name
    email
    createdAt
  }
"""

defgql :get_user, ~GQL"""
  query GetUser($id: ID!) {
    user(id: $id) {
      ...UserFields
    }
  }
"""
```

The fragment generates a typed module at `Client.Fragments.UserFields`.

## Configuration

Configuration is resolved in order (later wins): compile-time defaults -> runtime config -> per-call opts.

### Compile-time (in `use`)

```elixir
use Grephql,
  otp_app: :my_app,
  source: "priv/schemas/github.json",
  endpoint: "https://api.github.com/graphql",
  req_options: [receive_timeout: 30_000],
  scalars: %{"DateTime" => Grephql.Types.DateTime}
```

### Runtime (application config)

```elixir
# config/runtime.exs
config :my_app, MyApp.GitHub,
  endpoint: "https://api.github.com/graphql",
  req_options: [auth: {:bearer, System.fetch_env!("GITHUB_TOKEN")}]
```

### Per-call

```elixir
MyApp.GitHub.get_user(%{login: "octocat"},
  endpoint: "https://other.api.com/graphql",
  req_options: [receive_timeout: 60_000]
)
```

## The `~GQL` Sigil and Formatter

The `~GQL` sigil marks GraphQL strings for automatic formatting by `mix format`. Plain strings still work with `defgql` — `~GQL` is optional.

Add the formatter plugin to your `.formatter.exs`:

```elixir
[
  plugins: [Grephql.Formatter],
  # ...
]
```

Or via dependency import:

```elixir
[
  import_deps: [:grephql],
  # ...
]
```

### Before / After

```elixir
# Before
defgql :get_user, ~GQL"query GetUser($id: ID!) { user(id: $id) { name email posts { title } } }"

# After mix format
defgql :get_user, ~GQL"""
  query GetUser($id: ID!) {
    user(id: $id) {
      name
      email
      posts {
        title
      }
    }
  }
"""
```

## Custom Scalars

Map GraphQL custom scalars to Ecto types via the `:scalars` option:

```elixir
use Grephql,
  otp_app: :my_app,
  source: "schema.json",
  scalars: %{
    "DateTime" => Grephql.Types.DateTime,
    "JSON"     => :map
  }
```

`Grephql.Types.DateTime` is included for ISO 8601 DateTime strings. For other custom scalars, provide any module implementing the `Ecto.Type` behaviour.

## Unions and Interfaces

Union and interface types are resolved at decode time using the `__typename` field:

```elixir
defgql :search, ~GQL"""
  query Search($q: String!) {
    search(query: $q) {
      ... on User {
        name
      }
      ... on Repository {
        fullName
      }
    }
  }
"""
```

```elixir
{:ok, result} = MyApp.GitHub.search(%{q: "elixir"})

Enum.each(result.data.search, fn
  %{__typename: :user} = user -> IO.puts(user.name)
  %{__typename: :repository} = repo -> IO.puts(repo.full_name)
end)
```

## Generated Modules

Each `defgql` generates typed Ecto embedded schema modules at compile time. Given `defgql :get_user` inside `MyApp.GitHub`:

| Type | Pattern | Example |
|------|---------|---------|
| Result | `Client.FnName.Result.Field...` | `MyApp.GitHub.GetUser.Result.User` |
| Nested field | `...Result.Field.NestedField` | `MyApp.GitHub.GetUser.Result.User.Posts` |
| Variables | `Client.FnName.Variables` | `MyApp.GitHub.GetUser.Variables` |
| Input types | `Client.Inputs.TypeName` | `MyApp.GitHub.Inputs.CreateUserInput` |
| Fragment | `Client.Fragments.Name` | `MyApp.GitHub.Fragments.UserFields` |
| Union variant | `...Result.Field.TypeName` | `MyApp.GitHub.Search.Result.Search.User` |

### Naming rules

- Function name is CamelCased: `:get_user` -> `GetUser`
- Struct field names are snake_cased: `userName` -> `:user_name`
- Field aliases override both field name and module path: `author: user { ... }` -> field `:author`, module `...Result.Author`
- Input types are shared across queries under `Client.Inputs.*`
- Variables are per-query under `Client.FnName.Variables`
- Fragment modules live under `Client.Fragments.*`

### Example

```elixir
defmodule MyApp.GitHub do
  use Grephql, otp_app: :my_app, source: "schema.json"

  deffragment :post_fields, ~GQL"""
    fragment PostFields on Post {
      title
      body
    }
  """

  defgql :get_user, ~GQL"""
    query GetUser($id: ID!) {
      author: user(id: $id) {
        name
        posts {
          ...PostFields
        }
      }
    }
  """
end

# Generated modules:
# MyApp.GitHub.Fragments.PostFields         — %{title: String.t(), body: String.t()}
# MyApp.GitHub.GetUser.Result               — %{author: Author.t()}
# MyApp.GitHub.GetUser.Result.Author        — %{name: String.t(), posts: [Posts.t()]}
# MyApp.GitHub.GetUser.Result.Author.Posts   — %{title: String.t(), body: String.t()}
# MyApp.GitHub.GetUser.Variables            — %{id: String.t()}
```

## Testing

Use `Req.Test` to stub HTTP responses without any network calls:

```elixir
# config/test.exs
config :my_app, MyApp.GitHub,
  req_options: [plug: {Req.Test, MyApp.GitHub}]
```

```elixir
test "get_user returns user data" do
  Req.Test.stub(MyApp.GitHub, fn conn ->
    Req.Test.json(conn, %{
      "data" => %{"user" => %{"name" => "Alice", "bio" => "Elixirist"}}
    })
  end)

  assert {:ok, result} = MyApp.GitHub.get_user(%{login: "alice"})
  assert result.data.user.name == "Alice"
end
```

## Mix Tasks

### `mix grephql.download_schema`

Downloads a GraphQL schema via introspection and saves it as JSON.

```bash
mix grephql.download_schema --endpoint URL --output PATH [--header "Key: Value"]
```

| Option | Required | Description |
|--------|----------|-------------|
| `--endpoint` / `-e` | yes | GraphQL endpoint URL |
| `--output` / `-o` | yes | File path to save the schema JSON |
| `--header` / `-h` | no | HTTP header in `"Key: Value"` format (repeatable) |

## `use Grephql` Options

| Option | Required | Description |
|--------|----------|-------------|
| `:otp_app` | yes | OTP application for runtime config lookup |
| `:source` | yes | Path to introspection JSON (relative to caller file) or inline JSON string |
| `:endpoint` | no | Default GraphQL endpoint URL |
| `:req_options` | no | Default [Req options](https://hexdocs.pm/req/Req.html#new/1) (keyword list) |
| `:scalars` | no | Map of GraphQL scalar name to Ecto type (default: `%{}`) |

## Requirements

- Elixir ~> 1.15
- Erlang/OTP 24+

## License

See [LICENSE](LICENSE) for details.
