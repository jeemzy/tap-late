# Domain Docs

## Layout and reading rules

This repository uses a single context:

- `GLOSSARY.md` at the repository root holds domain terms.
- `docs/adr/` holds architectural decision records.

Before exploring domain concepts, read the glossary if present. Before working in an area, read the ADRs relevant to it.

When these files are absent, proceed silently. The domain-modeling skill creates them lazily as terms and decisions are resolved; setup does not create placeholder glossaries or ADRs.

## Vocabulary

Use glossary terms in issue titles, proposals, hypotheses, and test names. When a needed concept is missing, first check whether an existing term covers it; otherwise note the gap for domain modeling.

## Decision conflicts

If a proposal conflicts with an existing ADR, name the ADR and explain why the decision should be reopened. Keep the current decision explicit until it is superseded.
