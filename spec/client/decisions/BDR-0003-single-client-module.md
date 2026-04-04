---
id: BDR-0003
title: Single client module instead of schema/query separation
status: accepted
date: 2026-04-04
summary: One module handles schema binding, config, and query definitions — no separate schema module
---

**Feature**: client/features/client_module.feature
**Rule**: Client module is defined with use Grephql and otp_app

## Context

Initially considered separating schema modules (with a behaviour for fetching)
from query modules. Also considered using application config for schema source.

## Behaviours Considered

### Option A: Separate schema behaviour module + query module
Schema module implements `fetch_schema/0` callback, query module binds via
`use Grephql, schema: MyApp.Schema`.

### Option B: All config in application environment
`config :grephql, MyApp.Schema, source: "...", endpoint: "..."`.

### Option C: Single client module with use options + otp_app
`use Grephql, otp_app: :my_app, source: "..."` in one module.

## Decision

Chose Option C. The `use` macro executes at compile time, making schema source
reliably available for compilation. Runtime config (endpoint, headers) goes
through the standard `otp_app` pattern (like Ecto.Repo). No behaviour needed.

## Rejected Alternatives

**Option A** — Behaviour callbacks can't reliably run at compile time within
the same app (module compilation order is non-deterministic).

**Option B** — Elixir docs recommend against libraries using application
environment as global storage. Config should belong to the user's app, not
to `:grephql`.
