defmodule Grephql.LanguageTest do
  use ExUnit.Case, async: true

  alias Grephql.Language

  describe "Document" do
    test "default struct" do
      doc = %Language.Document{}
      assert doc.definitions == []
      assert doc.loc == %{line: nil}
    end
  end

  describe "Source" do
    test "default struct" do
      source = %Language.Source{}
      assert source.body == ""
      assert source.name == "GraphQL"
    end
  end

  describe "OperationDefinition" do
    test "default struct" do
      op = %Language.OperationDefinition{}
      assert op.operation == nil
      assert op.name == nil
      assert op.variable_definitions == []
      assert op.directives == []
      assert op.selection_set == nil
    end

    test "populated struct" do
      op = %Language.OperationDefinition{
        operation: :query,
        name: "GetUser",
        selection_set: %Language.SelectionSet{
          selections: [
            %Language.Field{name: "user"}
          ]
        }
      }

      assert op.operation == :query
      assert op.name == "GetUser"
      assert length(op.selection_set.selections) == 1
    end
  end

  describe "Field" do
    test "with alias and arguments" do
      field = %Language.Field{
        alias: "myUser",
        name: "user",
        arguments: [
          %Language.Argument{name: "id", value: %Language.Variable{name: "id"}}
        ],
        selection_set: %Language.SelectionSet{
          selections: [%Language.Field{name: "name"}]
        }
      }

      assert field.alias == "myUser"
      assert field.name == "user"
      assert length(field.arguments) == 1
      assert hd(field.arguments).value.name == "id"
    end
  end

  describe "VariableDefinition" do
    test "with type and default" do
      var_def = %Language.VariableDefinition{
        variable: %Language.Variable{name: "limit"},
        type: %Language.NamedType{name: "Int"},
        default_value: %Language.IntValue{value: 10}
      }

      assert var_def.variable.name == "limit"
      assert var_def.type.name == "Int"
      assert var_def.default_value.value == 10
    end
  end

  describe "Fragment and InlineFragment" do
    test "fragment struct" do
      frag = %Language.Fragment{
        name: "UserFields",
        type_condition: %Language.NamedType{name: "User"},
        selection_set: %Language.SelectionSet{
          selections: [%Language.Field{name: "name"}]
        }
      }

      assert frag.name == "UserFields"
      assert frag.type_condition.name == "User"
    end

    test "fragment spread" do
      spread = %Language.FragmentSpread{name: "UserFields"}
      assert spread.name == "UserFields"
      assert spread.directives == []
    end

    test "inline fragment" do
      inline = %Language.InlineFragment{
        type_condition: %Language.NamedType{name: "User"},
        selection_set: %Language.SelectionSet{
          selections: [%Language.Field{name: "name"}]
        }
      }

      assert inline.type_condition.name == "User"
    end
  end

  describe "Directive" do
    test "with arguments" do
      directive = %Language.Directive{
        name: "skip",
        arguments: [
          %Language.Argument{name: "if", value: %Language.BooleanValue{value: true}}
        ]
      }

      assert directive.name == "skip"
      assert hd(directive.arguments).value.value == true
    end
  end

  describe "value types" do
    test "IntValue" do
      assert %Language.IntValue{value: 42}.value == 42
    end

    test "FloatValue" do
      assert %Language.FloatValue{value: 3.14}.value == 3.14
    end

    test "StringValue" do
      assert %Language.StringValue{value: "hello"}.value == "hello"
    end

    test "BooleanValue" do
      assert %Language.BooleanValue{value: true}.value == true
    end

    test "NullValue" do
      assert %Language.NullValue{}.loc == nil
    end

    test "EnumValue" do
      assert %Language.EnumValue{value: "ACTIVE"}.value == "ACTIVE"
    end

    test "ListValue" do
      list = %Language.ListValue{
        values: [
          %Language.IntValue{value: 1},
          %Language.IntValue{value: 2}
        ]
      }

      assert length(list.values) == 2
    end

    test "ObjectValue with ObjectField" do
      obj = %Language.ObjectValue{
        fields: [
          %Language.ObjectField{name: "key", value: %Language.StringValue{value: "val"}}
        ]
      }

      assert hd(obj.fields).name == "key"
      assert hd(obj.fields).value.value == "val"
    end
  end

  describe "type references" do
    test "NamedType" do
      assert %Language.NamedType{name: "String"}.name == "String"
    end

    test "ListType wrapping NamedType" do
      list_type = %Language.ListType{
        type: %Language.NamedType{name: "User"}
      }

      assert list_type.type.name == "User"
    end

    test "NonNullType wrapping ListType" do
      nn = %Language.NonNullType{
        type: %Language.ListType{
          type: %Language.NonNullType{
            type: %Language.NamedType{name: "User"}
          }
        }
      }

      assert nn.type.type.type.name == "User"
    end
  end

  describe "type definitions" do
    test "ObjectTypeDefinition" do
      obj = %Language.ObjectTypeDefinition{
        name: "User",
        fields: [
          %Language.FieldDefinition{
            name: "name",
            type: %Language.NonNullType{type: %Language.NamedType{name: "String"}}
          }
        ]
      }

      assert obj.name == "User"
      assert hd(obj.fields).name == "name"
    end

    test "EnumTypeDefinition" do
      enum = %Language.EnumTypeDefinition{
        name: "Status",
        values: [
          %Language.EnumValueDefinition{value: "ACTIVE"},
          %Language.EnumValueDefinition{value: "INACTIVE"}
        ]
      }

      assert enum.name == "Status"
      assert length(enum.values) == 2
    end

    test "InputObjectTypeDefinition" do
      input = %Language.InputObjectTypeDefinition{
        name: "CreateUserInput",
        fields: [
          %Language.InputValueDefinition{
            name: "name",
            type: %Language.NonNullType{type: %Language.NamedType{name: "String"}}
          }
        ]
      }

      assert input.name == "CreateUserInput"
      assert hd(input.fields).name == "name"
    end

    test "UnionTypeDefinition" do
      union = %Language.UnionTypeDefinition{
        name: "SearchResult",
        types: [
          %Language.NamedType{name: "User"},
          %Language.NamedType{name: "Post"}
        ]
      }

      assert union.name == "SearchResult"
      assert length(union.types) == 2
    end

    test "InterfaceTypeDefinition" do
      iface = %Language.InterfaceTypeDefinition{
        name: "Node",
        fields: [
          %Language.FieldDefinition{name: "id", type: %Language.NamedType{name: "ID"}}
        ]
      }

      assert iface.name == "Node"
    end

    test "ScalarTypeDefinition" do
      scalar = %Language.ScalarTypeDefinition{name: "DateTime"}
      assert scalar.name == "DateTime"
    end
  end

  describe "schema definitions" do
    test "DirectiveDefinition" do
      dir = %Language.DirectiveDefinition{
        name: "skip",
        locations: [:FIELD, :FRAGMENT_SPREAD, :INLINE_FRAGMENT],
        arguments: [
          %Language.InputValueDefinition{
            name: "if",
            type: %Language.NonNullType{type: %Language.NamedType{name: "Boolean"}}
          }
        ]
      }

      assert dir.name == "skip"
      assert dir.repeatable == false
      assert length(dir.locations) == 3
    end

    test "SchemaDefinition" do
      schema = %Language.SchemaDefinition{
        fields: [
          %Language.FieldDefinition{name: "query", type: %Language.NamedType{name: "Query"}}
        ]
      }

      assert hd(schema.fields).name == "query"
    end

    test "TypeExtensionDefinition" do
      ext = %Language.TypeExtensionDefinition{
        definition: %Language.ObjectTypeDefinition{name: "User"}
      }

      assert ext.definition.name == "User"
    end
  end

  describe "full query AST" do
    test "builds a complete query AST" do
      ast = %Language.Document{
        definitions: [
          %Language.OperationDefinition{
            operation: :query,
            name: "GetUser",
            variable_definitions: [
              %Language.VariableDefinition{
                variable: %Language.Variable{name: "id"},
                type: %Language.NonNullType{type: %Language.NamedType{name: "ID"}}
              }
            ],
            selection_set: %Language.SelectionSet{
              selections: [
                %Language.Field{
                  name: "user",
                  arguments: [
                    %Language.Argument{
                      name: "id",
                      value: %Language.Variable{name: "id"}
                    }
                  ],
                  selection_set: %Language.SelectionSet{
                    selections: [
                      %Language.Field{name: "name"},
                      %Language.Field{name: "email"}
                    ]
                  }
                }
              ]
            }
          }
        ]
      }

      [op] = ast.definitions
      assert op.operation == :query
      assert op.name == "GetUser"
      assert length(op.variable_definitions) == 1

      [user_field] = op.selection_set.selections
      assert user_field.name == "user"
      assert length(user_field.selection_set.selections) == 2
    end
  end
end
