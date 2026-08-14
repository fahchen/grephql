defmodule TypedGql.Test.UnionTypes.Address do
  @moduledoc false
  use TypedGql.EmbeddedSchema

  typed_embedded_schema do
    field :zip, :string, typed: [null: true]
  end
end

defmodule TypedGql.Test.UnionTypes.User do
  @moduledoc false
  use TypedGql.EmbeddedSchema

  typed_embedded_schema do
    field :__typename, TypedGql.Types.Typename, values: ["User", "Post"], typed: [null: false]
    field :name, :string, typed: [null: true]
    field :email, :string, typed: [null: true]
    field :role, TypedGql.Types.Enum, values: ["ADMIN"], typed: [null: true]
    embeds_one :address, TypedGql.Test.UnionTypes.Address, typed: [null: true]
  end
end

defmodule TypedGql.Test.UnionTypes.Post do
  @moduledoc false
  use TypedGql.EmbeddedSchema

  typed_embedded_schema do
    field :__typename, TypedGql.Types.Typename, values: ["User", "Post"], typed: [null: false]
    field :title, :string, typed: [null: true]
  end
end

# A member that never selected __typename: the struct has no field to carry the
# variant's identity, so a dumped map only round-trips if Union.dump writes the
# key back from the module.
defmodule TypedGql.Test.UnionTypes.BareUser do
  @moduledoc false
  use TypedGql.EmbeddedSchema

  typed_embedded_schema do
    field :name, :string, typed: [null: true]
  end
end
