# Grephql 研究发现

## Absinthe Parser 分析

### Lexer
- 位置：`lib/absinthe/lexer.ex`
- 基于 NimbleParsec，不依赖 Absinthe 内部
- **高度可提取**，只需改 module namespace

### Parser
- 位置：`src/absinthe_parser.yrl`（Erlang yecc 文件）
- 语法自包含，helper 函数定义在同一文件
- **硬编码引用** `'Elixir.Absinthe.Language.*'` struct，需要全部替换
- 输出完整 AST：field name、arguments、variable definitions（带类型）、selection set、loc（行列号）

### AST 结构
- Document → definitions（Operation、Fragment）
- OperationDefinition → operation type、name、variables、directives、selection_set
- Field → name、alias、arguments、directives、selection_set、loc
- VariableDefinition → variable、type（NamedType/ListType/NonNullType）、default_value

### License
- Absinthe 使用 MIT 协议，可以自由 fork/修改
- 需要在 NOTICE 文件中注明来源

## TypedStructor
- 提供 `typed_structor` macro DSL
- 自动生成 `@type t()` spec
- `enforce: true` 对应 non-null 字段
- 未 enforce 且无 default 的字段自动包含 `| nil`
- `module: Name` 可创建子模块 struct
- 完美匹配 Grephql 的 struct 生成需求

## Elixir Config 最佳实践
- 库不应使用 application environment 作为全局存储
- 用户的配置应该属于用户的 app（`config :my_app, MyModule`），不是库的
- `use` macro 在编译时执行，可靠地提供编译时配置
- Runtime config 走 `otp_app` 模式（类似 Ecto.Repo）

## GraphQL Introspection Schema
- 标准 JSON 格式：`{"data": {"__schema": {...}}}`
- 包含 types、directives、queryType、mutationType
- 每个 type 有 fields、inputFields、enumValues、possibleTypes
- 每个 field 有 args、type、isDeprecated、deprecationReason
- Directive 有 name、locations、args
