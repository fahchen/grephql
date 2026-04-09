defmodule Grephql.Test.Response.ScalarUser do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :name, :string, typed: [null: false]
    field :email, :string, typed: [null: true]
  end
end

defmodule Grephql.Test.Response.NumericFields do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :age, :integer, typed: [null: false]
    field :score, :float, typed: [null: false]
  end
end

defmodule Grephql.Test.Response.BooleanField do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :active, :boolean, typed: [null: false]
  end
end

defmodule Grephql.Test.Response.Profile do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :bio, :string, typed: [null: true]
  end
end

defmodule Grephql.Test.Response.UserWithProfile do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :name, :string, typed: [null: false]
    embeds_one :profile, Grephql.Test.Response.Profile, typed: [null: true]
  end
end

defmodule Grephql.Test.Response.Post do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :title, :string, typed: [null: false]
  end
end

defmodule Grephql.Test.Response.UserWithPosts do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :name, :string, typed: [null: false]
    embeds_many :posts, Grephql.Test.Response.Post, typed: []
  end
end

defmodule Grephql.Test.Response.DeepAuthor do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :name, :string, typed: [null: false]
  end
end

defmodule Grephql.Test.Response.DeepPost do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :title, :string, typed: [null: false]
    embeds_one :author, Grephql.Test.Response.DeepAuthor, typed: []
  end
end

defmodule Grephql.Test.Response.UserWithDeepPosts do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :name, :string, typed: [null: false]
    embeds_many :posts, Grephql.Test.Response.DeepPost, typed: []
  end
end

defmodule Grephql.Test.Response.UserWithRole do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :name, :string, typed: [null: false]
    field :role, Grephql.Types.Enum, values: ["ADMIN", "USER", "GUEST"], typed: [null: true]
  end
end

defmodule Grephql.Test.Response.WithDateTime do
  @moduledoc false
  use Grephql.EmbeddedSchema

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :name, :string, typed: [null: false]
    field :created_at, Grephql.Types.DateTime, typed: [null: true]
  end
end
