defmodule Grephql.Test.UnionTypes.User do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :__typename, :string, typed: [null: false]
    field :name, :string, typed: [null: true]
    field :email, :string, typed: [null: true]
  end
end

defmodule Grephql.Test.UnionTypes.Post do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :__typename, :string, typed: [null: false]
    field :title, :string, typed: [null: true]
  end
end
