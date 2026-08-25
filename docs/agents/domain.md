# Domain Docs

These rules describe how engineering skills consume this repository's domain documentation.

## Before exploring

- Read `CONTEXT.md` at the repository root when it exists.
- Read ADRs under `docs/adr/` that affect the area being changed.
- If either location does not exist, proceed silently. Domain-modeling work creates the documents when terminology or a decision has actually been resolved.

## Layout

This is a single-context repository:

```text
/
|- CONTEXT.md
|- docs/adr/
`- src/
```

## Vocabulary

Use terms defined in the `CONTEXT.md` glossary consistently in issues, tests, design proposals, and implementation. If a required concept is missing, reconsider whether a new term is necessary or record the gap for domain-modeling work.

## ADR conflicts

Explicitly flag any proposal that conflicts with an existing ADR instead of silently overriding the recorded decision.
