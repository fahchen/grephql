# Grephql

Compile-time GraphQL client for Elixir. Validates queries against your schema at compile time and generates typed Ecto embedded schemas for responses.

## Features

- **Compile-time validation** — catches invalid fields, wrong argument types, missing variables before your code runs
- **Typed responses** — every query generates Ecto embedded schemas, so you pattern match on structs instead of digging through maps
- **Unions & interfaces** — dispatches to the correct struct based on `__typename`, match with normal Elixir pattern matching
- **Custom scalars** — plug in your own `Ecto.Type` modules for non-standard scalars
- **Req-based HTTP** — uses [Req](https://github.com/wojtekmach/req) with full middleware/plugin support

## Installation

```elixir
def deps do
  [
    {:grephql, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Get your schema

Export your GraphQL introspection schema as JSON and save it to your project:

```bash
# Example using graphql-inspector
graphql-inspector introspect https://api.example.com/graphql --write priv/schemas/example.json
```

### 2. Define a client module

```elixir
defmodule MyApp.GitHub do
  use Grephql,
    otp_app: :my_app,
    source: "priv/schemas/github.json"

  defgql :get_user, """
  query GetUser($login: String!) {
    user(login: $login) {
      name
      email
      avatarUrl
    }
  }
  """
end
```

This generates at compile time:

- `MyApp.GitHub.get_user/1,2` — a function that executes the query
- `MyApp.GitHub.GetUser.Result.User` — a typed struct for the response
- `MyApp.GitHub.GetUser.Variables` — a typed struct for variables

### 3. Execute

```elixir
case MyApp.GitHub.get_user(%{login: "alice"}) do
  {:ok, %{data: %{user: user}}} ->
    IO.puts(user.name)    # "Alice"
    IO.puts(user.email)   # "alice@example.com"

  {:ok, %{errors: errors}} ->
    IO.inspect(errors)

  {:error, response} ->
    IO.inspect(response)
end
```

## Configuration

### Compile-time options

Passed to `use Grephql`:

| Option | Required | Description |
|---|---|---|
| `:otp_app` | yes | OTP app name for runtime config lookup |
| `:source` | yes | Path to schema JSON (relative to file) or inline JSON string |
| `:scalars` | no | Custom scalar mappings: `%{"DateTime" => MyApp.Types.DateTime}` |
| `:endpoint` | no | Default GraphQL endpoint URL |
| `:req_options` | no | Default [Req options](https://hexdocs.pm/req/Req.html#new/1) |

### Runtime configuration

Override at runtime via application config:

```elixir
# config/runtime.exs
config :my_app, MyApp.GitHub,
  endpoint: "https://api.github.com/graphql",
  req_options: [
    auth: {:bearer, System.fetch_env!("GITHUB_TOKEN")},
    receive_timeout: 30_000
  ]
```

### Per-call overrides

```elixir
MyApp.GitHub.get_user(
  %{login: "alice"},
  endpoint: "https://staging-api.github.com/graphql"
)
```

Configuration resolves in order: compile-time defaults < runtime config < per-call options.

## Macros & Sigils

### `defgql` / `defgqlp`

Define public or private query functions:

```elixir
# Public
defgql :get_user, "query GetUser($login: String!) { user(login: $login) { name } }"

# Private
defgqlp :fetch_repos, "query { viewer { repositories(first: 10) { nodes { name } } } }"
```

Queries without variables generate a zero-arity function:

```elixir
defgql :current_user, "query { viewer { login } }"

# Usage:
{:ok, result} = MyApp.GitHub.current_user()
```

### `~g` sigil

Compile a query into a `%Grephql.Query{}` struct without generating a function:

```elixir
@query ~g"query GetUser($login: String!) { user(login: $login) { name } }"
```

Supports interpolation with module attributes:

```elixir
@user_fields "name email avatarUrl"
@query ~g"query GetUser($login: String!) { user(login: $login) { #{@user_fields} } }"
```

## Type Mapping

### Built-in scalars

| GraphQL | Elixir |
|---|---|
| `String` | `:string` |
| `Int` | `:integer` |
| `Float` | `:float` |
| `Boolean` | `:boolean` |
| `ID` | `:string` |
| `DateTime` | `Grephql.Types.DateTime` (ISO 8601) |

### Custom scalars

```elixir
use Grephql,
  otp_app: :my_app,
  source: "priv/schemas/api.json",
  scalars: %{
    "JSON" => MyApp.Types.JSON,
    "Decimal" => MyApp.Types.Decimal
  }
```

Each custom scalar module must implement the `Ecto.Type` behaviour.

### Enums

GraphQL enums become atoms. `"ADMIN"` casts to `:admin`, `"READ_ONLY"` to `:read_only`.

### Unions & interfaces

GraphQL unions dispatch to the correct Elixir struct based on `__typename`:

```elixir
defgql :search, """
query Search($q: String!) {
  search(query: $q) {
    ... on User { name }
    ... on Repository { fullName }
  }
}
"""

{:ok, %{data: %{search: results}}} = MyApp.GitHub.search(%{q: "elixir"})

Enum.each(results, fn
  %MyApp.GitHub.Search.Result.Search.User{} = user -> IO.puts(user.name)
  %MyApp.GitHub.Search.Result.Search.Repository{} = repo -> IO.puts(repo.full_name)
end)
```

## Testing

Use `Req.Test` for HTTP mocking (no external mock library needed):

```elixir
# config/test.exs
config :my_app, MyApp.GitHub,
  req_options: [plug: {Req.Test, MyApp.GitHub}]

# In your test
Req.Test.stub(MyApp.GitHub, fn conn ->
  Req.Test.json(conn, %{
    "data" => %{
      "user" => %{"name" => "Alice", "email" => "alice@example.com"}
    }
  })
end)

assert {:ok, %{data: %{user: user}}} = MyApp.GitHub.get_user(%{login: "alice"})
assert user.name == "Alice"
```

## Field Aliases

GraphQL aliases are fully supported — they affect both the struct field name and the module path:

```elixir
defgql :get_account, """
query {
  account: user(login: "alice") {
    displayName: name
  }
}
"""

{:ok, %{data: %{account: account}}} = MyApp.GitHub.get_account()
account.display_name  # uses the alias as the field name
```

## License

MIT
