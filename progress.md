# Grephql 进度日志

## 2026-04-04 — BDD Discovery + 实现计划

### 完成
- ✅ BDD Discovery 完成，所有业务规则已确认
- ✅ 生成 5 个 feature 文件（compile_time_validation, type_generation, query_definition, client_module, compilation_cache）
- ✅ 生成 5 个 BDR（no-subscription, no-fragment-merging, single-client-module, union-as-struct-match, fork-absinthe-parser）
- ✅ Glossary 完成
- ✅ Consistency check 通过（修复了 2 个问题）
- ✅ 所有 spec 文件已 commit（85da120）
- ✅ 7 阶段实现计划制定完成

### 关键决策
- Parser：fork Absinthe 的 yecc + NimbleParsec lexer
- 模块模式：单一 client module（use + otp_app）
- 类型生成：TypedStructor，output per-query 隔离，input schema-level
- Union：direct struct match + __typename（弃用 tagged tuple）
- Scalar：behaviour + shorthand tuple 两种形式
- 编译缓存：schema hash + query hash 双层缓存

### 下一步
- 开始阶段 1：基础设施（Parser + Schema 加载）
