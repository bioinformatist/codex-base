---
name: docs-routing
description: Route requests for current library, framework, SDK, API, CLI, or cloud-service documentation through available documentation tools and primary sources.
---

# Documentation Routing

Use this route for current product documentation unless a higher-authority product-specific documentation workflow applies.

Before each lookup:

- Ask for the missing documentation fact or closely related facts, rather than passing the whole implementation task to the provider.
- Separate independent products or topics into focused queries. Combine them when the question concerns their interaction or a comparison.
- Include the exact product and requested version; add the repository owner or technical context when names are ambiguous (for example, `mistral.rs` with Apple's Metal backend). Set the tool's `product` field when available.

Follow this provider order for each lookup:

1. Use `context7` to resolve the exact library and version. The plugin default is anonymous, but native same-name configuration may replace it with an authenticated connection.
2. Accept only nonempty, relevant results that cover the requested version and include traceable source URLs.
3. When `context7` is anonymous and rate-limited, unavailable, or insufficient, use `context7_auth` if available and apply the same acceptance test.
4. Then fall back to official primary documentation or source.
5. Never send secrets, credentials, private code, full prompts, or non-public internal content to either connection.
6. If a named tool is absent, advance without automatically installing, authenticating, or retrying it. A host authentication prompt leaves the call pending; after it is resolved or dismissed, evaluate the result and continue when insufficient.
