---
id: BDR-0001
title: No subscription support
status: accepted
date: 2026-04-04
summary: No subscription transport; a subscription compiles and validates like any operation but is executed as an HTTP POST
---

**Feature**: client/features/query_definition.feature
**Rule**: N/A (scope boundary)

## Decision

The boundary is transport, not compilation. A subscription operation parses,
validates against the schema's subscription root, and generates result types
like a query or a mutation does — and is then POSTed over HTTP, which no server
answers as a stream. There is no WebSocket support and none is planned here.

## Reason

Subscriptions require WebSocket transport, which is fundamentally different from
the HTTP request/response model that Req handles. Supporting subscriptions would
add significant complexity (connection management, reconnection, message framing)
for a feature that can be addressed separately. The client focuses on HTTP-based
query and mutation operations.
