defmodule TypedGql.Language do
  @moduledoc false

  @type selection_t() ::
          TypedGql.Language.Field.t()
          | TypedGql.Language.FragmentSpread.t()
          | TypedGql.Language.InlineFragment.t()

  @type value_t() ::
          TypedGql.Language.IntValue.t()
          | TypedGql.Language.FloatValue.t()
          | TypedGql.Language.StringValue.t()
          | TypedGql.Language.BooleanValue.t()
          | TypedGql.Language.NullValue.t()
          | TypedGql.Language.EnumValue.t()
          | TypedGql.Language.ListValue.t()
          | TypedGql.Language.ObjectValue.t()
          | TypedGql.Language.Variable.t()

  @type type_reference_t() ::
          TypedGql.Language.NamedType.t()
          | TypedGql.Language.ListType.t()
          | TypedGql.Language.NonNullType.t()

  @type definition_t() ::
          TypedGql.Language.OperationDefinition.t()
          | TypedGql.Language.Fragment.t()
          | TypedGql.Language.SchemaDefinition.t()
          | TypedGql.Language.SchemaDeclaration.t()
          | TypedGql.Language.ObjectTypeDefinition.t()
          | TypedGql.Language.InterfaceTypeDefinition.t()
          | TypedGql.Language.UnionTypeDefinition.t()
          | TypedGql.Language.EnumTypeDefinition.t()
          | TypedGql.Language.ScalarTypeDefinition.t()
          | TypedGql.Language.InputObjectTypeDefinition.t()
          | TypedGql.Language.DirectiveDefinition.t()
          | TypedGql.Language.TypeExtensionDefinition.t()

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
      field :definitions, [TypedGql.Language.definition_t()], default: []
      field :loc, map(), default: %{line: nil}
    end

    @doc """
    The document's fragment definitions, keyed by name.

    A repeated name keeps the last definition, matching the shadowing rule
    everywhere else: the latest definition wins.
    """
    @spec fragments_by_name(t()) :: %{String.t() => TypedGql.Language.Fragment.t()}
    def fragments_by_name(%__MODULE__{definitions: definitions}) do
      for %TypedGql.Language.Fragment{} = fragment <- definitions,
          into: %{},
          do: {fragment.name, fragment}
    end
  end

  @doc """
  Whether a variable definition's default value can stand in for a missing one.

  `nil` means the definition declared no default. A `NullValue` declared one
  that is null, which satisfies nothing a non-null type promises — so neither
  makes the variable optional, nor lets it reach a non-null argument.
  """
  @spec usable_default?(TypedGql.Language.value_t() | nil) :: boolean()
  def usable_default?(nil), do: false
  def usable_default?(%TypedGql.Language.NullValue{}), do: false
  def usable_default?(_value), do: true

  @doc """
  Every fragment spread name in a selection set, depth first, duplicates kept.
  """
  @spec spread_names(TypedGql.Language.SelectionSet.t() | nil) :: [String.t()]
  def spread_names(nil), do: []

  def spread_names(%TypedGql.Language.SelectionSet{selections: selections}) do
    Enum.flat_map(selections, fn
      %TypedGql.Language.FragmentSpread{name: name} -> [name]
      %{selection_set: selection_set} -> spread_names(selection_set)
    end)
  end
end
