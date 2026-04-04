defmodule Grephql.Language do
  @moduledoc false

  @type selection_t() ::
          Grephql.Language.Field.t()
          | Grephql.Language.FragmentSpread.t()
          | Grephql.Language.InlineFragment.t()

  @type value_t() ::
          Grephql.Language.IntValue.t()
          | Grephql.Language.FloatValue.t()
          | Grephql.Language.StringValue.t()
          | Grephql.Language.BooleanValue.t()
          | Grephql.Language.NullValue.t()
          | Grephql.Language.EnumValue.t()
          | Grephql.Language.ListValue.t()
          | Grephql.Language.ObjectValue.t()
          | Grephql.Language.Variable.t()

  @type type_reference_t() ::
          Grephql.Language.NamedType.t()
          | Grephql.Language.ListType.t()
          | Grephql.Language.NonNullType.t()

  @type definition_t() ::
          Grephql.Language.OperationDefinition.t()
          | Grephql.Language.Fragment.t()
          | Grephql.Language.SchemaDefinition.t()
          | Grephql.Language.SchemaDeclaration.t()
          | Grephql.Language.ObjectTypeDefinition.t()
          | Grephql.Language.InterfaceTypeDefinition.t()
          | Grephql.Language.UnionTypeDefinition.t()
          | Grephql.Language.EnumTypeDefinition.t()
          | Grephql.Language.ScalarTypeDefinition.t()
          | Grephql.Language.InputObjectTypeDefinition.t()
          | Grephql.Language.DirectiveDefinition.t()
          | Grephql.Language.TypeExtensionDefinition.t()

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
      field :definitions, [Grephql.Language.definition_t()], default: []
      field :loc, map(), default: %{line: nil}
    end
  end
end
