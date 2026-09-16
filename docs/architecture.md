# Architecture

## Goal

SpaceWright provides a portable engine for turning validated workspace
configuration into predictable macOS Space and window state. It preserves
explicit workflow behavior while separating personal facts from mutation
mechanics.

## Runtime Layers

```text
public Fish commands
        |
        v
configuration loader and validator
        |
        v
snapshot -> plan -> preflight -> apply -> verify
        |                            |
        v                            v
display/space/window model      bounded recovery adapters
        |
        v
yabai + jq (+ optional System Events fallbacks)
```

### Public command layer

Stable Fish commands remain the user-facing API. During migration, thin
wrappers may dispatch either to the legacy implementation or the configured
runner. Command names do not encode package installation paths.

### Configuration layer

The configuration layer loads package defaults and user configuration, checks
the schema version, rejects unsupported or ambiguous definitions, and produces
one deterministic effective configuration.

It owns declarative facts:

- app keys and accepted names;
- workspace ids and labels;
- display roles;
- required and optional window roles;
- explainable window selectors;
- grid or bounded geometry actions;
- mode composition and simple cleanup policy.

It does not own execution logic, shell fragments, arbitrary jq, retries, or
app-specific recovery programs.

### Snapshot and plan layer

One read-only snapshot captures displays, Spaces, and windows for a planning
operation. Planning resolves configuration against that snapshot and explains:

- the target display and Space;
- selected and missing windows;
- ownership conflicts;
- planned movement and layouts;
- cleanup and finalization actions.

Planning must be idempotent and non-mutating.

### Apply and verify layer

Application begins only after configuration and required-window preflight
passes. Mutations use bounded yabai wrappers, confirm final ownership, apply
layout, finalize ordering/cleanup, and verify the resulting contract.

### Recovery adapters

Some applications expose non-standard or transient windows. Explicit Fish
adapters may implement bounded recovery for these cases. Recovery remains code
because making JSON a programming language would make plans unsafe and hard to
review.

## Roots And State

The final runtime will distinguish:

- **package root**: versioned SpaceWright code, schema, and defaults;
- **configuration root**: user-authored portable configuration;
- **state root**: machine-local UUIDs, caches, and runtime observations.

The exact installer paths are a Phase 2 decision. Regardless of location, the
runtime must resolve them explicitly and must not infer one root from another.

## Integration Boundary

skhd triggers commands but does not define runtime behavior. displayplacer
profiles arrange monitors but do not express workspace intent. yabai provides
the low-level Space/window API but does not own SpaceWright configuration.

SpaceWright may ship examples and adapters for these tools. It must not replace
or overwrite a user's live configuration silently.

## Consumer/Provider Model

SpaceWright is a versioned provider. The Mackup repository is the initial
consumer:

```text
SpaceWright release or immutable commit
                  |
                  v
          Mackup version pin
                  |
                  +--> user configuration
                  +--> skhd integration
                  +--> display profiles
```

Cross-repository integration is one-directional at runtime. SpaceWright never
imports Mackup source files. Mackup exposes configuration at the documented
configuration root and selects the SpaceWright version it consumes.

## Failure Model

The runtime fails closed before mutation on:

- missing or unsupported configuration versions;
- schema or jq failure;
- display query/resolution failure;
- missing required windows;
- ambiguous label or ownership state that cannot be safely retargeted.

After mutation begins, operations are bounded, observable, and verified. A
failure returns non-zero and preserves enough diagnostic context for explicit
recovery; it must not trigger an unbounded retry loop.

## Evolution Strategy

The imported runtime is a behavioral baseline. Evolution is intentionally
staged:

1. preserve history and behavior;
2. make paths relocatable without changing semantics;
3. introduce read-only configuration and comparison;
4. migrate a simple workspace behind a bypass;
5. expand only after fixture and daily-use evidence.

This keeps deterministic runtime mechanics separate from personal workflow
design and makes each architectural change independently reversible.
