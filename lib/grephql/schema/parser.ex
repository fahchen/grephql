defmodule Grephql.Schema.Parser do
  @moduledoc false

  alias Grephql.Schema
  alias Grephql.Schema.Directive
  alias Grephql.Schema.EnumValue
  alias Grephql.Schema.Field
  alias Grephql.Schema.InputValue
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef

  @spec parse(String.t()) :: {:ok, Schema.t()} | {:error, String.t()}
  def parse(json) when is_binary(json) do
    case Grephql.JSON.decode(json) do
      {:ok, %{"data" => %{"__schema" => schema}}} ->
        {:ok, build_schema(schema)}

      {:ok, %{"__schema" => schema}} ->
        {:ok, build_schema(schema)}

      {:ok, _} ->
        {:error, "invalid introspection result: missing __schema"}

      {:error, error} ->
        {:error, "JSON decode error: #{format_json_error(error)}"}
    end
  end

  defp build_schema(schema) do
    types = build_types(schema["types"] || [])

    %Schema{
      query_type: get_in(schema, ["queryType", "name"]),
      mutation_type: get_in(schema, ["mutationType", "name"]),
      subscription_type: get_in(schema, ["subscriptionType", "name"]),
      types: types,
      directives: build_directives(schema["directives"] || [])
    }
  end

  defp build_types(types) do
    Map.new(types, fn type ->
      {type["name"], build_type(type)}
    end)
  end

  defp build_type(type) do
    %Type{
      kind: parse_kind(type["kind"]),
      name: type["name"],
      description: type["description"],
      fields: build_fields(type["fields"]),
      input_fields: build_input_values_map(type["inputFields"]),
      interfaces: build_type_names(type["interfaces"]),
      enum_values: build_enum_values(type["enumValues"]),
      possible_types: build_type_names(type["possibleTypes"]),
      of_type: build_type_ref(type["ofType"])
    }
  end

  defp build_fields(nil), do: %{}

  defp build_fields(fields) do
    Map.new(fields, fn field ->
      {field["name"], build_field(field)}
    end)
  end

  defp build_field(field) do
    %Field{
      name: field["name"],
      description: field["description"],
      type: build_type_ref(field["type"]),
      args: build_input_values_map(field["args"]),
      is_deprecated: field["isDeprecated"] || false,
      deprecation_reason: field["deprecationReason"]
    }
  end

  defp build_input_values_map(nil), do: %{}

  defp build_input_values_map(input_values) do
    Map.new(input_values, fn iv ->
      {iv["name"], build_input_value(iv)}
    end)
  end

  defp build_input_value(iv) do
    %InputValue{
      name: iv["name"],
      description: iv["description"],
      type: build_type_ref(iv["type"]),
      default_value: iv["defaultValue"],
      is_deprecated: iv["isDeprecated"] || false,
      deprecation_reason: iv["deprecationReason"]
    }
  end

  defp build_enum_values(nil), do: []

  defp build_enum_values(values) do
    Enum.map(values, fn v ->
      %EnumValue{
        name: v["name"],
        description: v["description"],
        is_deprecated: v["isDeprecated"] || false,
        deprecation_reason: v["deprecationReason"]
      }
    end)
  end

  defp build_type_names(nil), do: []
  defp build_type_names(types), do: Enum.map(types, & &1["name"])

  defp build_type_ref(nil), do: nil

  defp build_type_ref(ref) do
    %TypeRef{
      kind: parse_kind(ref["kind"]),
      name: ref["name"],
      of_type: build_type_ref(ref["ofType"])
    }
  end

  defp build_directives(directives) do
    Enum.map(directives, fn d ->
      %Directive{
        name: d["name"],
        description: d["description"],
        locations: Enum.map(d["locations"] || [], &parse_location/1),
        args: build_input_values_map(d["args"])
      }
    end)
  end

  @kind_map %{
    "SCALAR" => :scalar,
    "OBJECT" => :object,
    "INTERFACE" => :interface,
    "UNION" => :union,
    "ENUM" => :enum,
    "INPUT_OBJECT" => :input_object,
    "LIST" => :list,
    "NON_NULL" => :non_null
  }

  defp parse_kind(kind) when is_map_key(@kind_map, kind), do: @kind_map[kind]

  @location_map %{
    "QUERY" => :query,
    "MUTATION" => :mutation,
    "SUBSCRIPTION" => :subscription,
    "FIELD" => :field,
    "FRAGMENT_DEFINITION" => :fragment_definition,
    "FRAGMENT_SPREAD" => :fragment_spread,
    "INLINE_FRAGMENT" => :inline_fragment,
    "VARIABLE_DEFINITION" => :variable_definition,
    "SCHEMA" => :schema,
    "SCALAR" => :scalar,
    "OBJECT" => :object,
    "FIELD_DEFINITION" => :field_definition,
    "ARGUMENT_DEFINITION" => :argument_definition,
    "INTERFACE" => :interface,
    "UNION" => :union,
    "ENUM" => :enum,
    "ENUM_VALUE" => :enum_value,
    "INPUT_OBJECT" => :input_object,
    "INPUT_FIELD_DEFINITION" => :input_field_definition
  }

  defp parse_location(loc) when is_map_key(@location_map, loc), do: @location_map[loc]

  defp format_json_error(error) when is_exception(error), do: Exception.message(error)
  defp format_json_error(error), do: inspect(error)
end
