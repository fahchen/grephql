defmodule TypedGql.Test.Variables.Metadata do
  @moduledoc false
  use TypedGql.EmbeddedSchema

  typed_embedded_schema do
    field :slug, :string
    field :seo_title, :string, source: :seoTitle
  end
end

defmodule TypedGql.Test.Variables.Tag do
  @moduledoc false
  use TypedGql.EmbeddedSchema

  typed_embedded_schema do
    field :name, :string
    field :color_hex, :string, source: :colorHex
  end
end

defmodule TypedGql.Test.Variables.Input do
  @moduledoc false
  use TypedGql.EmbeddedSchema

  typed_embedded_schema do
    field :title, :string
    field :body, :string
    embeds_one :metadata, TypedGql.Test.Variables.Metadata
    embeds_many :tags, TypedGql.Test.Variables.Tag
  end
end

defmodule TypedGql.Test.Variables.Params do
  @moduledoc false
  use TypedGql.EmbeddedSchema

  typed_embedded_schema do
    field :id, :string
    field :show_email, :boolean, source: :showEmail
    embeds_one :input, TypedGql.Test.Variables.Input
  end
end
