---
name: docs-routing
description: Route requests for current library, framework, SDK, API, CLI, or cloud-service documentation through available documentation tools and primary sources.
---

# Documentation Routing

Use this route for current product documentation unless a higher-authority product-specific documentation workflow applies.

1. Query `mintlify_index` once with focused product and requested-version terms.
2. Accept the result only when it is nonempty, relevant, covers the requested version, and includes traceable source URLs.
3. Otherwise use anonymous `context7` to resolve the exact library and version. Do not repeat an equivalent Mintlify query.
4. Use `context7_auth` only when it is available and anonymous Context7 is rate-limited, unavailable, or still insufficient.
5. Then fall back to official primary documentation or source.
6. Never send secrets, credentials, private code, full prompts, or non-public internal content to either provider.
7. If a named tool is absent, advance to the next stage without automatically installing, authenticating, or retrying it.
