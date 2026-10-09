---
name: domain-modeling
description: Build and sharpen a project's domain model. Use only when actively changing glossary or ubiquitous-language terms, or recording a durable architectural decision; merely reading a glossary is not a trigger.
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline: challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* `GLOSSARY.md` for vocabulary is not this skill: that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

## File structure

Most repos have a single context:

```
/
├── GLOSSARY.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If `GLOSSARY-MAP.md` or `CONTEXT-MAP.md` exists at the root, read its pointers to find the existing contexts:

```
/
├── GLOSSARY-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── GLOSSARY.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── GLOSSARY.md
│       └── docs/adr/
```

Use existing GLOSSARY.md or CONTEXT.md files and their map pointers; do not migrate or duplicate them. When authorized to write and no glossary exists, create GLOSSARY.md for the first resolved term. Create docs/adr/ only for the first accepted ADR. Otherwise render the exact proposed change in chat.

## During the session

### Challenge against the glossary

When a term conflicts with the existing GLOSSARY.md or CONTEXT.md language, surface the conflict. "Your glossary defines 'cancellation' as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account': do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible. Which is right?"

### Update the existing glossary inline

When a term is resolved and writing is authorized, update the existing glossary, or GLOSSARY.md for a new one. Otherwise render the exact proposed update in chat. Don't batch these up: capture them as they happen. Use the format in [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md).

Keep the existing GLOSSARY.md or CONTEXT.md focused on domain terms, without implementation details or decisions. Use ADRs for durable decisions.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).
