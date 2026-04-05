defmodule Grephql.InputTypeGenerator do
  @moduledoc """
  Generates Ecto embedded schema modules for GraphQL input types.

  Unlike `TypeGenerator` (per-query output types), input types are
  schema-level and shared across queries. Each input object type
  generates one module under `ClientModule.Inputs.InputTypeName`.

  Generated modules include a `build/1` function that validates
  parameters via Ecto changeset and returns `{:ok, struct}` or
  `{:error, changeset}`.
  """

  alias Grephql.GeneratorHelpers
  alias Grephql.Language.ListType
  alias Grephql.Language.NamedType
  alias Grephql.Language.NonNullType
  alias Grephql.Schema
  alias Grephql.TypeMapper
  alias Grephql.Validator.Helpers

  alias Grephql.Schema.TypeRef

  @type option() :: {:client_module, module()} | {:function_name, atom()} | {:scalar_types, map()}

  @doc """
  Generates input type modules for all input types referenced by
  an operation's variable definitions.

  Returns a list of generated module names.

  ## Options

    - `:client_module` — the parent client module (e.g., `MyApp.UserService`)
    - `:scalar_types` — custom scalar type mappings (default: `%{}`)
  """
  @spec generate(Grephql.Language.OperationDefinition.t(), Schema.t(), [option()]) :: [module()]
  def generate(operation, schema, opts) do
    client_module = Keyword.fetch!(opts, :client_module)
    scalar_types = Keyword.get(opts, :scalar_types, %{})

    # Input module names derived from schema at compile time
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    inputs_module = Module.concat(client_module, "Inputs")
    context = {schema, scalar_types, inputs_module}

    operation.variable_definitions
    |> collect_input_type_names(schema)
    |> Enum.flat_map(&generate_input_type(&1, context))
  end

  @doc """
  Generates a Variables struct for an operation's variable definitions.

  Returns the Variables module name, or `nil` if the operation has no variables.
  Variable field names are snake_cased with `source:` mapping to the original
  GraphQL variable name for correct serialization via `Ecto.embedded_dump/2`.

  ## Options

    - `:client_module` — the parent client module
    - `:function_name` — the defgql function name (for module path)
    - `:scalar_types` — custom scalar type mappings (default: `%{}`)
  """
  @spec generate_variables(
          Grephql.Language.OperationDefinition.t(),
          Schema.t(),
          [option()]
        ) :: module() | nil
  def generate_variables(operation, _schema, _opts) when operation.variable_definitions == [] do
    nil
  end

  def generate_variables(operation, schema, opts) do
    client_module = Keyword.fetch!(opts, :client_module)
    function_name = Keyword.fetch!(opts, :function_name)
    scalar_types = Keyword.get(opts, :scalar_types, %{})

    # Module names derived from schema at compile time
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    inputs_module = Module.concat(client_module, "Inputs")
    # Module names derived from schema at compile time
    # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
    variables_module =
      Module.concat([client_module, GeneratorHelpers.camelize(function_name), Variables])

    context = {schema, scalar_types, inputs_module}

    {field_defs, embed_names, required_names} =
      Enum.reduce(operation.variable_definitions, {[], [], []}, fn var_def,
                                                                   {defs, embeds, reqs} ->
        var_name = var_def.variable.name
        type_ref = language_type_to_type_ref(var_def.type, schema)
        resolved = TypeMapper.resolve(type_ref, scalar_types)

        # Variable names from query, bounded set
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        atom_name = var_name |> Macro.underscore() |> String.to_atom()
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        source_atom = String.to_atom(var_name)

        req = if resolved.nullable, do: reqs, else: [atom_name | reqs]

        build_variable_field(
          atom_name,
          source_atom,
          resolved,
          context,
          {defs, embeds, req}
        )
      end)

    {field_defs, cast_fields, embed_names, required_names} =
      GeneratorHelpers.prepare_schema_fields(field_defs, embed_names, required_names)

    create_input_schema(variables_module, field_defs, cast_fields, embed_names, required_names)

    variables_module
  end

  defp build_variable_field(atom_name, source_atom, resolved, context, {defs, embeds, reqs}) do
    source_opt = if atom_name != source_atom, do: [source: source_atom], else: []

    case resolved.ecto_type do
      {:object, nested_type_name} ->
        {field_def, _new_modules} =
          build_input_embed(:embeds_one, atom_name, nested_type_name, resolved, context)

        {[field_def | defs], [atom_name | embeds], reqs}

      {:array, {:object, nested_type_name}} ->
        {field_def, _new_modules} =
          build_input_embed(:embeds_many, atom_name, nested_type_name, resolved, context)

        {[field_def | defs], [atom_name | embeds], reqs}

      ecto_type ->
        typed_opts = if resolved.nullable, do: [null: true], else: [null: false]
        field_def = {:field, atom_name, ecto_type, [{:typed, typed_opts} | source_opt]}
        {[field_def | defs], embeds, reqs}
    end
  end

  defp language_type_to_type_ref(%NonNullType{type: inner}, schema) do
    %TypeRef{kind: :non_null, of_type: language_type_to_type_ref(inner, schema)}
  end

  defp language_type_to_type_ref(%ListType{type: inner}, schema) do
    %TypeRef{kind: :list, of_type: language_type_to_type_ref(inner, schema)}
  end

  defp language_type_to_type_ref(%NamedType{name: name}, schema) do
    case Schema.get_type(schema, name) do
      {:ok, type} -> %TypeRef{kind: type.kind, name: name}
      :error -> %TypeRef{kind: :scalar, name: name}
    end
  end

  defp collect_input_type_names(variable_definitions, schema) do
    variable_definitions
    |> Enum.map(fn var_def -> unwrap_language_type(var_def.type) end)
    |> Enum.uniq()
    |> Enum.filter(fn name ->
      case Schema.get_type(schema, name) do
        {:ok, %{kind: :input_object}} -> true
        _other -> false
      end
    end)
  end

  defp unwrap_language_type(%NamedType{name: name}), do: name
  defp unwrap_language_type(%ListType{type: inner}), do: unwrap_language_type(inner)
  defp unwrap_language_type(%NonNullType{type: inner}), do: unwrap_language_type(inner)

  defp generate_input_type(type_name, {schema, _scalar_types, inputs_module} = context) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    module = Module.concat(inputs_module, Macro.camelize(type_name))

    if Code.ensure_loaded?(module) do
      []
    else
      {:ok, type} = Schema.get_type(schema, type_name)
      generate_module(module, type, context)
    end
  end

  defp generate_module(module, type, {_schema, scalar_types, _inputs_module} = context) do
    {field_defs, embed_names, required_names, nested_modules} =
      type.input_fields
      |> Enum.sort_by(fn {name, _input_value} -> name end)
      |> Enum.reduce({[], [], [], []}, fn {_name, input_value}, acc ->
        # Input field names from GraphQL schema, bounded set
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        atom_name = input_value.name |> Macro.underscore() |> String.to_atom()
        resolved = TypeMapper.resolve(input_value.type, scalar_types)
        build_input_field(atom_name, input_value, resolved, context, acc)
      end)

    {field_defs, cast_fields, embed_names, required_names} =
      GeneratorHelpers.prepare_schema_fields(field_defs, embed_names, required_names)

    create_input_schema(module, field_defs, cast_fields, embed_names, required_names)

    [module | List.flatten(:lists.reverse(nested_modules))]
  end

  defp build_input_field(atom_name, input_value, resolved, context, {defs, embeds, reqs, nested}) do
    req = if Helpers.required?(input_value), do: [atom_name], else: []

    case resolved.ecto_type do
      {:object, nested_type_name} ->
        {field_def, new_modules} =
          build_input_embed(:embeds_one, atom_name, nested_type_name, resolved, context)

        {[field_def | defs], [atom_name | embeds], req ++ reqs, [new_modules | nested]}

      {:array, {:object, nested_type_name}} ->
        {field_def, new_modules} =
          build_input_embed(:embeds_many, atom_name, nested_type_name, resolved, context)

        {[field_def | defs], [atom_name | embeds], req ++ reqs, [new_modules | nested]}

      ecto_type ->
        typed_opts = if resolved.nullable, do: [null: true], else: [null: false]
        field_def = {:field, atom_name, ecto_type, [typed: typed_opts]}
        {[field_def | defs], embeds, req ++ reqs, nested}
    end
  end

  defp build_input_embed(kind, atom_name, nested_type_name, resolved, context) do
    new_modules = generate_input_type(nested_type_name, context)
    {_schema, _scalar_types, inputs_module} = context

    # Nested input module names from schema, bounded set
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    nested_module = Module.concat(inputs_module, Macro.camelize(nested_type_name))

    typed_opts = GeneratorHelpers.embed_typed_opts(kind, resolved)
    {{kind, atom_name, nested_module, [typed: typed_opts]}, new_modules}
  end

  defp create_input_schema(module_name, field_defs, cast_fields, embed_names, required_names) do
    field_asts = Enum.map(field_defs, &GeneratorHelpers.field_def_to_ast/1)
    params_type_ast = GeneratorHelpers.build_params_type_ast(field_defs, required_names)
    changeset_body = changeset_body_ast(cast_fields, embed_names, required_names)

    Module.create(
      module_name,
      quote do
        use Grephql.EmbeddedSchema
        import Ecto.Changeset

        @type params() :: unquote(params_type_ast)

        typed_embedded_schema do
          (unquote_splicing(field_asts))
        end

        @doc false
        @spec changeset(t(), map()) :: Ecto.Changeset.t()
        def changeset(struct \\ %__MODULE__{}, params) do
          unquote(changeset_body)
        end

        @doc """
        Validates and builds a struct from the given parameters.

        Returns `{:ok, struct}` on success, `{:error, changeset}` on failure.
        """
        @spec build(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
        def build(params) when is_map(params) do
          %__MODULE__{}
          |> changeset(params)
          |> apply_action(:build)
        end
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp changeset_body_ast(cast_fields, embed_names, required_names) do
    ast = quote do: cast(struct, params, unquote(cast_fields))

    ast =
      Enum.reduce(embed_names, ast, fn name, acc ->
        quote do: cast_embed(unquote(acc), unquote(name))
      end)

    quote do: validate_required(unquote(ast), unquote(required_names))
  end
end
