defmodule Grephql.Language.SchemaDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :description, String.t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :fields, [Grephql.Language.FieldDefinition.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.SchemaDeclaration do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :description, String.t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :fields, [Grephql.Language.FieldDefinition.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.DirectiveDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :arguments, [Grephql.Language.InputValueDefinition.t()], default: []
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :locations, [atom()], default: []
    field :repeatable, boolean(), default: false
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.TypeExtensionDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :definition, Grephql.Language.ObjectTypeDefinition.t()
    field :loc, map(), default: %{line: nil}
  end
end
