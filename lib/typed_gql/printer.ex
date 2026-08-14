defmodule TypedGql.Printer do
  @moduledoc false

  alias TypedGql.Language.Argument
  alias TypedGql.Language.BooleanValue
  alias TypedGql.Language.Directive
  alias TypedGql.Language.EnumValue
  alias TypedGql.Language.Field
  alias TypedGql.Language.FloatValue
  alias TypedGql.Language.Fragment
  alias TypedGql.Language.FragmentSpread
  alias TypedGql.Language.InlineFragment
  alias TypedGql.Language.IntValue
  alias TypedGql.Language.ListType
  alias TypedGql.Language.ListValue
  alias TypedGql.Language.NamedType
  alias TypedGql.Language.NonNullType
  alias TypedGql.Language.NullValue
  alias TypedGql.Language.ObjectField
  alias TypedGql.Language.ObjectValue
  alias TypedGql.Language.OperationDefinition
  alias TypedGql.Language.SelectionSet
  alias TypedGql.Language.StringValue
  alias TypedGql.Language.Variable
  alias TypedGql.Language.VariableDefinition

  @indent "  "

  @spec print(TypedGql.Language.Document.t()) :: String.t()
  def print(%TypedGql.Language.Document{definitions: definitions}) do
    Enum.map_join(definitions, "\n\n", &print_definition/1)
  end

  defp print_definition(%OperationDefinition{shorthand: true} = op) do
    IO.iodata_to_binary(selection_set_iodata(op.selection_set, 0))
  end

  defp print_definition(%OperationDefinition{} = op) do
    IO.iodata_to_binary([
      Atom.to_string(op.operation),
      if(op.name, do: [" ", op.name], else: []),
      case op.variable_definitions do
        [] -> []
        vars -> ["(", join_iodata(vars, &variable_definition_iodata/1), ")"]
      end,
      directives_iodata(op.directives),
      " ",
      selection_set_iodata(op.selection_set, 0)
    ])
  end

  defp print_definition(%Fragment{} = frag) do
    IO.iodata_to_binary([
      "fragment ",
      frag.name,
      " on ",
      frag.type_condition.name,
      directives_iodata(frag.directives),
      " ",
      selection_set_iodata(frag.selection_set, 0)
    ])
  end

  defp selection_set_iodata(nil, _depth), do: []
  defp selection_set_iodata(%SelectionSet{selections: []}, _depth), do: []

  defp selection_set_iodata(%SelectionSet{selections: selections}, depth) do
    inner = Enum.map(selections, &selection_iodata(&1, depth + 1))
    indent = String.duplicate(@indent, depth)
    ["{\n", Enum.intersperse(inner, "\n"), "\n", indent, "}"]
  end

  defp selection_iodata(%Field{} = field, depth) do
    indent = String.duplicate(@indent, depth)

    [
      indent,
      if(field.alias, do: [field.alias, ": ", field.name], else: field.name),
      case field.arguments do
        [] -> []
        args -> ["(", join_iodata(args, &argument_iodata/1), ")"]
      end,
      directives_iodata(field.directives),
      if field.selection_set && field.selection_set.selections != [] do
        [" ", selection_set_iodata(field.selection_set, depth)]
      else
        []
      end
    ]
  end

  defp selection_iodata(%InlineFragment{} = frag, depth) do
    indent = String.duplicate(@indent, depth)

    [
      indent,
      "...",
      if(frag.type_condition, do: [" on ", frag.type_condition.name], else: []),
      directives_iodata(frag.directives),
      " ",
      selection_set_iodata(frag.selection_set, depth)
    ]
  end

  defp selection_iodata(%FragmentSpread{} = spread, depth) do
    indent = String.duplicate(@indent, depth)
    [indent, "...", spread.name, directives_iodata(spread.directives)]
  end

  defp variable_definition_iodata(%VariableDefinition{} = var_def) do
    [
      "$",
      var_def.variable.name,
      ": ",
      type_ref_iodata(var_def.type),
      if(var_def.default_value, do: [" = ", value_iodata(var_def.default_value)], else: []),
      directives_iodata(var_def.directives)
    ]
  end

  defp argument_iodata(%Argument{} = arg) do
    [arg.name, ": ", value_iodata(arg.value)]
  end

  defp directives_iodata([]), do: []

  defp directives_iodata(directives) do
    Enum.map(directives, fn
      %Directive{arguments: []} = dir ->
        [" @", dir.name]

      %Directive{} = dir ->
        [" @", dir.name, "(", join_iodata(dir.arguments, &argument_iodata/1), ")"]
    end)
  end

  defp type_ref_iodata(%NamedType{name: name}), do: name
  defp type_ref_iodata(%ListType{type: inner}), do: ["[", type_ref_iodata(inner), "]"]
  defp type_ref_iodata(%NonNullType{type: inner}), do: [type_ref_iodata(inner), "!"]

  defp value_iodata(%Variable{name: name}), do: ["$", name]
  defp value_iodata(%IntValue{value: val}), do: Integer.to_string(val)
  defp value_iodata(%FloatValue{value: val}), do: Float.to_string(val)
  defp value_iodata(%StringValue{value: val}), do: [?", escape_string(val), ?"]
  defp value_iodata(%BooleanValue{value: val}), do: Atom.to_string(val)
  defp value_iodata(%NullValue{}), do: "null"
  defp value_iodata(%EnumValue{value: val}), do: val

  defp value_iodata(%ListValue{values: values}) do
    ["[", join_iodata(values, &value_iodata/1), "]"]
  end

  defp value_iodata(%ObjectValue{fields: fields}) do
    ["{", join_iodata(fields, &object_field_iodata/1), "}"]
  end

  defp object_field_iodata(%ObjectField{} = field) do
    [field.name, ": ", value_iodata(field.value)]
  end

  defp join_iodata(items, mapper) do
    items |> Enum.map(mapper) |> Enum.intersperse(", ")
  end

  # The lexer decodes every escape the spec allows, so printing has to put them
  # back — the printed document is what gets sent, and a raw control byte inside
  # a string literal is not valid GraphQL.
  @escapes %{
    ?\\ => "\\\\",
    ?" => "\\\"",
    ?\n => "\\n",
    ?\r => "\\r",
    ?\t => "\\t",
    ?\b => "\\b",
    ?\f => "\\f"
  }

  defp escape_string(str) do
    for <<codepoint::utf8 <- str>>, into: "", do: escape_codepoint(codepoint)
  end

  defp escape_codepoint(codepoint) when is_map_key(@escapes, codepoint),
    do: Map.fetch!(@escapes, codepoint)

  defp escape_codepoint(codepoint) when codepoint < 0x20,
    do: "\\u" <> (codepoint |> Integer.to_string(16) |> String.pad_leading(4, "0"))

  defp escape_codepoint(codepoint), do: <<codepoint::utf8>>
end
