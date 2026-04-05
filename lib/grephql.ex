defmodule Grephql do
  @moduledoc """
  Compile-time GraphQL client for Elixir.

  Validates GraphQL operations at compile time and generates typed
  Ecto embedded schemas for responses.

  ## Usage

      defmodule MyApp.GitHub do
        use Grephql,
          otp_app: :my_app,
          source: "priv/schemas/github.json"

        defgql :get_user, "query($login: String!) { user(login: $login) { name } }"
      end
  """

  alias Grephql.Query

  @doc """
  Executes a compiled GraphQL query.

  Takes a `%Grephql.Query{}` struct (produced by `defgql` or `~GQL`),
  a map of variables, and optional keyword options.

  Options override runtime config which overrides compile-time defaults.
  """
  @spec execute(Query.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(query, variables \\ %{}, opts \\ [])

  def execute(%Query{} = _query, _variables, _opts) do
    {:error, :not_implemented}
  end
end
