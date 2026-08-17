defmodule TypedGql.IntegrationCase do
  @moduledoc """
  Case template for the integration suite (`test/integration/`).

  Verifies on exit that every `Req.Test` expectation set by a test was
  consumed — which also proves a test that set none made no HTTP call.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias TypedGql.Result
    end
  end

  setup {Req.Test, :verify_on_exit!}
end
