---
id: BDR-0001
title: No subscription support
status: accepted
date: 2026-04-04
summary: Only query and mutation operations supported; subscriptions excluded from scope
---

**Feature**: client/features/query_definition.feature
**Rule**: N/A (scope boundary)

## Reason

Subscriptions require WebSocket transport, which is fundamentally different from
the HTTP request/response model that Req handles. Supporting subscriptions would
add significant complexity (connection management, reconnection, message framing)
for a feature that can be addressed separately. The client focuses on HTTP-based
query and mutation operations.
