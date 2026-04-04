# Grephql 实现计划

## 项目概述
Grephql 是一个编译时 GraphQL 客户端库，利用 Elixir compiler 在编译时校验 GraphQL 操作，生成类型化 struct，并通过 Req 在运行时执行查询。

## 原则
- 每个步骤独立可测试、可 commit
- 小步提交，不积累大改动
- 测试用 mimic 做 mock

## 阶段规划

### 阶段 1：基础设施 — Parser + Schema 加载
**状态**：⬜ 未开始

#### 1.1 项目依赖配置
- [ ] 添加 deps：nimble_parsec, req, jason, typed_structor, mimic
- [ ] `mix deps.get` 确认编译通过
- **commit**: `add project dependencies`

#### 1.2 Fork Absinthe lexer
- [ ] 复制 Absinthe lexer → `lib/grephql/lexer.ex`
- [ ] 改 namespace 为 `Grephql.Lexer`
- [ ] 测试：tokenize 基本 query string
- **commit**: `add GraphQL lexer (forked from Absinthe)`

#### 1.3 定义 Grephql AST structs
- [ ] `Grephql.Language.Document`
- [ ] `Grephql.Language.OperationDefinition`
- [ ] `Grephql.Language.Field`, `Argument`, `Variable`, `VariableDefinition`
- [ ] `Grephql.Language.SelectionSet`, `InlineFragment`
- [ ] `Grephql.Language.Directive`
- [ ] `Grephql.Language.NamedType`, `ListType`, `NonNullType`
- [ ] `Grephql.Language.IntValue`, `FloatValue`, `StringValue`, `BooleanValue`, `EnumValue`, `ListValue`, `ObjectValue`, `ObjectField`
- **commit**: `define GraphQL AST structs`

#### 1.4 Fork Absinthe yecc parser
- [ ] 复制 `absinthe_parser.yrl` → `src/grephql_parser.yrl`
- [ ] 替换所有 `Absinthe.Language.*` → `Grephql.Language.*`
- [ ] 编写 `Grephql.Parser.parse/1` 封装 lexer + yecc
- [ ] 测试：parse 简单 query、mutation、带 variables、带 directives
- **commit**: `add GraphQL parser (forked from Absinthe)`

#### 1.5 NOTICE 文件
- [ ] 创建 NOTICE 文件，注明 Absinthe MIT attribution
- **commit**: `add NOTICE for Absinthe attribution`

#### 1.6 Introspection schema 数据结构
- [ ] `Grephql.Schema` — 内部 schema 表示（types index、fields lookup）
- [ ] `Grephql.Schema.Type` — type 定义（object, input, enum, union, interface, scalar）
- [ ] `Grephql.Schema.Field` — field 定义（name, type, args, isDeprecated, deprecationReason）
- [ ] `Grephql.Schema.Directive` — directive 定义（name, locations, args）
- [ ] 测试：数据结构基本创建和查找
- **commit**: `define introspection schema data structures`

#### 1.7 Introspection JSON 解析器
- [ ] `Grephql.Schema.parse/1` — 标准 introspection JSON → `%Grephql.Schema{}`
- [ ] 构建类型索引（by name lookup）
- [ ] 测试：解析样本 introspection JSON，验证类型/字段查找
- **commit**: `add introspection JSON parser`

#### 1.8 Schema source 加载器
- [ ] `Grephql.Schema.Loader` — 根据 source 选项加载原始 JSON
- [ ] 支持文件路径
- [ ] 支持 inline string
- [ ] 测试
- **commit**: `add schema source loader`


---

### 阶段 2：编译时校验
**状态**：⬜ 未开始
**依赖**：阶段 1

#### 2.1 Validator 框架
- [ ] `Grephql.Validator` — 校验 pipeline（接收 AST + Schema，返回 errors + warnings）
- [ ] `Grephql.Validator.Error` — 统一错误结构（message, loc, severity）
- [ ] 测试：空 pipeline 通过，错误收集机制
- **commit**: `add validator framework`

#### 2.2 Operation 校验
- [ ] root type 存在性
- [ ] 匿名 operation 单一性
- [ ] operation name 唯一性
- [ ] 测试
- **commit**: `add operation structure validation`

#### 2.3 Field 校验
- [ ] 字段存在性
- [ ] scalar 不可有子选择
- [ ] composite 必须有子选择
- [ ] 空 selection set
- [ ] 测试
- **commit**: `add field validation`

#### 2.4 Argument 校验
- [ ] 参数存在性
- [ ] 必填参数
- [ ] 类型匹配
- [ ] 唯一性
- [ ] 测试
- **commit**: `add argument validation`

#### 2.5 Variable 校验
- [ ] 类型匹配
- [ ] 已定义/已使用
- [ ] 唯一性
- [ ] 测试
- **commit**: `add variable validation`

#### 2.6 Directive 校验
- [ ] 存在性
- [ ] 位置合法性
- [ ] 参数校验
- [ ] 不可重复
- [ ] 测试
- **commit**: `add directive validation`

#### 2.7 Inline fragment + type condition 校验
- [ ] type condition 合法性（union/interface 成员）
- [ ] 测试
- **commit**: `add inline fragment validation`

#### 2.8 Input object 校验（inline literal）
- [ ] 字段存在性
- [ ] 必填字段
- [ ] 唯一性
- [ ] 测试
- **commit**: `add input object validation`

#### 2.9 Enum + custom scalar 校验
- [ ] enum 值有效性
- [ ] custom scalar 映射存在性（behaviour / tuple / built-in）
- [ ] 测试
- **commit**: `add enum and custom scalar validation`

#### 2.10 Deprecation 检测
- [ ] deprecated field → warning
- [ ] deprecated enum value → warning
- [ ] 测试
- **commit**: `add deprecation warning detection`

---

### 阶段 3：类型生成
**状态**：⬜ 未开始
**依赖**：阶段 1

#### 3.1 Grephql.Error struct
- [ ] 定义 `%Grephql.Error{message, path, locations, extensions}`
- [ ] 测试
- **commit**: `add Grephql.Error struct`

#### 3.2 Grephql.Scalar behaviour
- [ ] 定义 behaviour：`type/0`, `serialize/1`, `deserialize/1`
- [ ] Shorthand tuple 解析：`{type, ser_fn, deser_fn}`
- [ ] 内置 scalar 模块（`Grephql.Scalar.DateTime` 等）
- [ ] 测试
- **commit**: `add Grephql.Scalar behaviour and built-ins`

#### 3.3 类型映射引擎
- [ ] `Grephql.TypeMapper` — GraphQL type → Elixir type AST
- [ ] 标量映射（String → String.t(), Int → integer(), etc.）
- [ ] Nullable → `| nil`
- [ ] List 组合
- [ ] Enum → downcased atom union
- [ ] Custom scalar → 用户配置的类型
- [ ] 测试
- **commit**: `add type mapper (GraphQL types to Elixir types)`

#### 3.4 Union/Interface 映射
- [ ] `:struct` 模式 → direct struct union
- [ ] `:map` 模式 → `__typename` keyed map union
- [ ] 测试
- **commit**: `add union and interface type mapping`

#### 3.5 Struct 生成器 — output types
- [ ] `Grephql.TypeGenerator` — 从 query AST + schema 生成 TypedStructor module AST
- [ ] Field path naming（`ClientModule.FunctionName.FieldName`）
- [ ] Per-query 隔离
- [ ] 全递归嵌套
- [ ] 测试
- **commit**: `add output type struct generator`

#### 3.6 Struct 生成器 — input types
- [ ] Schema-level naming（`ClientModule.InputTypeName`）
- [ ] 跨 query 共享
- [ ] 测试
- **commit**: `add input type struct generator`

#### 3.7 type_style 支持
- [ ] `:struct` — 嵌套 struct
- [ ] `:map` — typed map
- [ ] `:query_shape` — 按 query 选择字段的 struct（field path naming）
- [ ] 测试
- **commit**: `add type_style configuration support`

---

### 阶段 4：Client Module 宏（核心 API）
**状态**：⬜ 未开始
**依赖**：阶段 2 + 3

#### 4.1 Grephql.Query struct
- [ ] 定义 `%Grephql.Query{document, schema_context, result_type, variables_type}`
- [ ] 测试
- **commit**: `add Grephql.Query struct`

#### 4.2 `use Grephql` 基础
- [ ] 宏接收 `otp_app`, `source`, `type_style`, `scalars`
- [ ] 编译时加载 + 解析 schema
- [ ] 注入 `sigil_GQL/2`
- [ ] 测试：use 宏编译通过，schema 可用
- **commit**: `add use Grephql macro with schema loading`

#### 4.3 `~GQL` sigil
- [ ] 编译时 parse + validate + 生成 query struct
- [ ] 支持字符串插值
- [ ] 测试：sigil 返回 query struct，校验失败 → compile error
- **commit**: `add ~GQL sigil implementation`

#### 4.4 `defgql/defgqlp` 宏
- [ ] 编译时 parse + validate + type generation
- [ ] 生成函数签名（有/无 variables）
- [ ] 生成 typespec
- [ ] 测试：函数生成正确，typespec 正确
- **commit**: `add defgql and defgqlp macros`

#### 4.5 Config 优先级链
- [ ] `execute opts > runtime config > use options > defaults`
- [ ] `Grephql.Config` 模块处理合并逻辑
- [ ] 测试
- **commit**: `add config priority chain`

---

### 阶段 5：运行时执行
**状态**：⬜ 未开始
**依赖**：阶段 4

#### 5.1 Variable 序列化
- [ ] Custom scalar serialize
- [ ] Enum atom → uppercase string
- [ ] Input struct → map 转换
- [ ] 测试
- **commit**: `add variable serialization`

#### 5.2 `Grephql.execute/3`
- [ ] 通过 Req 发送 HTTP POST
- [ ] Endpoint 解析（config 优先级链）
- [ ] Headers 合并
- [ ] 测试（mimic mock Req）
- **commit**: `add Grephql.execute with Req HTTP client`

#### 5.3 Response 反序列化
- [ ] JSON data → 生成的 struct/map
- [ ] Custom scalar deserialize
- [ ] Union dispatch（struct / `__typename`）
- [ ] Errors → `[%Grephql.Error{}]`
- [ ] 返回 `{:ok, %{data: typed, errors: list}}` 或 `{:error, reason}`
- [ ] 测试
- **commit**: `add response deserialization`

#### 5.4 defgql 函数内部接线
- [ ] 生成的函数调用 Grephql.execute
- [ ] 测试：端到端调用（mimic mock Req）
- **commit**: `wire defgql functions to Grephql.execute`

#### 5.5 mix grephql.download_schema
- [ ] Mix task：从远端 endpoint 下载 introspection schema 到本地文件
- [ ] 支持 `--endpoint`, `--output`, `--header` 参数
- [ ] 发送标准 introspection query
- [ ] 测试（mimic mock Req）
- **commit**: `add mix grephql.download_schema task`

---

### 阶段 6：编译缓存
**状态**：⬜ 未开始
**依赖**：阶段 4

#### 6.1 Schema content hash + 缓存
- [ ] 计算 schema source 内容 hash
- [ ] 缓存解析后的 schema（写入 `_build`）
- [ ] 测试
- **commit**: `add schema compilation cache`

#### 6.2 Query content hash + 缓存
- [ ] schema hash + query string hash → 缓存 key
- [ ] 缓存生成的 struct + function AST
- [ ] Schema 变更 → 失效所有 query cache
- [ ] 测试
- **commit**: `add query compilation cache`

#### 6.3 按需生成
- [ ] 只处理被 defgql / ~GQL 引用的类型
- [ ] 跳过未引用的 schema 类型
- [ ] 测试
- **commit**: `add on-demand type generation`

---

### 阶段 7：集成测试 + 文档
**状态**：⬜ 未开始
**依赖**：阶段 5 + 6

#### 7.1 集成测试
- [ ] 端到端测试（用 mimic mock Req + 样本 schema）
- [ ] 多 schema 场景
- [ ] 各种 type_style
- **commit**: `add integration tests`

#### 7.2 文档
- [ ] @moduledoc / @doc
- [ ] README 使用指南
- **commit**: `add documentation`

#### 7.3 NOTICE 文件
- [ ] Absinthe MIT attribution（如果 1.5 未做）
- **commit**: `add NOTICE file` (如果需要)

---

## 关键决策记录
| 决策 | 选择 | BDR |
|------|------|-----|
| Subscription 支持 | 不支持，只做 query + mutation | BDR-0001 |
| Fragment 复用 | 字符串插值，不做 sigil 层合并 | BDR-0002 |
| 模块模式 | 单一 client module（use + otp_app） | BDR-0003 |
| Union/Interface 映射 | Direct struct match + __typename | BDR-0004 |
| Parser 来源 | Fork Absinthe yecc + NimbleParsec lexer | BDR-0005 |
| Mock 库 | Mimic | — |

## 依赖关系
```
阶段1（Parser+Schema）
  ├── 阶段2（校验）──┐
  └── 阶段3（类型）──┤
                     └── 阶段4（宏 API）
                          ├── 阶段5（运行时）
                          └── 阶段6（缓存）
                               └── 阶段7（测试+文档）
```

## Commit 统计
- 阶段 1：8 commits
- 阶段 2：10 commits
- 阶段 3：7 commits
- 阶段 4：5 commits
- 阶段 5：5 commits
- 阶段 6：3 commits
- 阶段 7：2-3 commits
- **总计：约 40-41 commits**
