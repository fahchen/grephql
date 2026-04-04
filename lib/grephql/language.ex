defmodule Grephql.Language do
  @moduledoc false

  defmodule Source do
    @moduledoc false
    use TypedStructor

    typed_structor do
      field :body, String.t(), default: ""
      field :name, String.t(), default: "GraphQL"
    end
  end

  defmodule Document do
    @moduledoc false
    use TypedStructor

    typed_structor do
      field :definitions, [any()], default: []
      field :loc, map(), default: %{line: nil}
    end
  end
end
