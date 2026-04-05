defmodule Grephql.Printer do
  @moduledoc false

  alias Grephql.Language.Argument
  alias Grephql.Language.BooleanValue
  alias Grephql.Language.Directive
  alias Grephql.Language.EnumValue
  alias Grephql.Language.Field
  alias Grephql.Language.FloatValue
  alias Grephql.Language.Fragment
  alias Grephql.Language.FragmentSpread
  alias Grephql.Language.InlineFragment
  alias Grephql.Language.IntValue
  alias Grephql.Language.ListType
  alias Grephql.Language.ListValue
  alias Grephql.Language.NamedType
  alias Grephql.Language.NonNullType
  alias Grephql.Language.NullValue
  alias Grephql.Language.ObjectField
  alias Grephql.Language.ObjectValue
  alias Grephql.Language.OperationDefinition
  alias Grephql.Language.SelectionSet
  alias Grephql.Language.StringValue
  alias Grephql.Language.Variable
  alias Grephql.Language.VariableDefinition

  @indent "  "

  @spec print(Grephql.Language.Document.t()) :: String.t()
  def print(%Grephql.Language.Document{definitions: definitions}) do
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

  defp escape_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
