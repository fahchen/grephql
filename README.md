# Grephql

Compile-time GraphQL client for Elixir. Parses and validates queries during compilation, generates typed Ecto embedded schemas for responses and variables, and executes queries at runtime via [Req](https://github.com/wojtekmach/req).

## Features

- **Compile-time validation** — GraphQL syntax errors and schema mismatches caught at `mix compile`
- **Typed responses** — Auto-generated Ecto embedded schemas for query results
- **Typed variables** — Input validation via Ecto changesets with generated `params()` type
- **Zero runtime parsing** — All GraphQL parsing happens at compile time
- **Req integration** — Full access to Req's middleware/plugin system, including `Req.Test` for testing

## Installation

Add `grephql` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:grephql, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Download your schema

Use the built-in Mix task to download your GraphQL schema via introspection:

```bash
mix grephql.download_schema \
  --endpoint https://api.example.com/graphql \
  --output priv/schemas/schema.json \
  --header "Authorization: Bearer token123"
```

This sends an introspection query, validates the response, and saves it as JSON.

### 2. Define a client module

```elixir
defmodule MyApp.GitHub do
  use Grephql,
    otp_app: :my_app,
    source: "priv/schemas/github.json",
    endpoint: "https://api.github.com/graphql"

  defgql :get_user, "query GetUser($login: String!) { user(login: $login) { name bio } }"

  defgql :get_viewer, "query { viewer { login email } }"
end
```

`defgql` parses and validates the query at compile time, generates typed response/variable modules, and defines a function you can call at runtime.

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

## Configuration

Configuration is resolved in order (later wins): compile-time defaults -> runtime config -> `execute/3` opts.

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

## The `~g` Sigil

For cases where you need the compiled query struct without a generated function, use the `~g` sigil:

```elixir
defmodule MyApp.GitHub do
  use Grephql,
    otp_app: :my_app,
    source: "priv/schemas/github.json"

  @query ~g"query GetUser($login: String!) { user(login: $login) { name } }"

  def run do
    Grephql.execute(@query, %{login: "octocat"})
  end
end
```

The operation must be named (`query GetUser`, not just `query`).

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
defgql :search, """
query Search($q: String!) {
  search(query: $q) {
    ... on User { name }
    ... on Repository { fullName }
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

- Elixir ~> 1.19
- Erlang/OTP 27+

## License

See [LICENSE](LICENSE) for details.
