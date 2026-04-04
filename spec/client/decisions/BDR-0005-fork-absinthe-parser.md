---
id: BDR-0005
title: Fork Absinthe's yecc parser and NimbleParsec lexer
status: accepted
date: 2026-04-04
summary: Vendor Absinthe's parser (yecc + NimbleParsec lexer) into Grephql, replacing Absinthe.Language structs with Grephql's own AST
---

**Feature**: client/features/compile_time_validation.feature
**Rule**: All validation rules

## Context

Grephql needs a GraphQL query parser to produce AST for compile-time validation.
Options were: depend on Absinthe, fork its parser, or write from scratch.

## Behaviours Considered

### Option A: Depend on Absinthe
Full framework as dependency — immediate access to parser and AST.

### Option B: Fork yecc + lexer from Absinthe
Copy `absinthe_parser.yrl` and `Absinthe.Lexer` into Grephql, rename AST
structs. MIT license, attribute in NOTICE file.

### Option C: Write parser from scratch with NimbleParsec
Full control, no external code, but significant effort for spec compliance.

## Decision

Chose Option B. Absinthe's parser is battle-tested, MIT licensed, and uses
standard Erlang tooling (yecc). The lexer only depends on NimbleParsec.
Forking gives us full control over AST structure without pulling in the
entire Absinthe framework. GraphQL query syntax is stable — maintenance
burden is low.

## Rejected Alternatives

**Option A** — Pulling in an entire GraphQL server framework as a dependency
for a client library is inappropriate. Most of Absinthe's code is irrelevant.

**Option C** — Reinventing a spec-compliant parser is significant work with
diminishing returns. The yecc grammar is already correct and well-tested.
