---
name: feature-specs
description: Turn a project description and feature list into a directory of functional spec files — one markdown file per feature, plus an INDEX and an optional shared core.md. Each spec captures observable behavior, behavioral requirements, edge cases, acceptance criteria, dependencies, open questions, and explicit non-goals, while deliberately avoiding implementation details so specs stay resilient to how features actually get built. The skill works depth-first — it reads what's there, confirms the feature list, then for each feature asks targeted clarifying questions before writing its spec. Use this whenever the user wants to spec features, plan a project, break a roadmap into actionable units, draft a build plan, turn a README or design notes into per-feature specs, or do any "spec this out" / "write up specs for these features" / "help me plan how to build X" / "break this into chunks I can work on" style work — even when they don't say the word "spec" explicitly.
---

# Feature Specs

You take a project description plus a list of features and produce a directory of functional spec files — one per feature, an `INDEX.md` linking them, and optionally a `core.md` for shared concepts. Each spec describes what the feature *does* — its observable behavior, requirements, edge cases, and acceptance criteria — without prescribing how it's built.

The point of these specs is that they survive implementation churn. Internal class layouts, data structures, file organization, library choices — all of that will change over the life of a feature. What shouldn't change is what the feature *does* from the outside. That's what a spec captures, and that's why the work of writing one is worth it.

## Core principle: no implementation

This is the rule the skill lives or dies by. **A spec must not describe implementation.** It describes what's observable to someone using the feature.

The test: *can someone outside the system observe this?* If yes, it belongs in the spec. If no — if it's an internal data structure, a class name, a code organization decision, a choice of library, an internal protocol between components — it does not.

Watch for things that *sound* like behavior but aren't. "The parser emits `node_open` before `text` opcodes" sounds like behavior, but `node_open` is an internal protocol — that's implementation. The corresponding behavioral statement is something like *"when the input contains a heading followed by body text, downstream consumers see the heading as a container of that text."*

| Implementation leak | Behavioral rewrite |
|---|---|
| Store notes in a `notes` table with columns `id`, `title`, `body`, `created_at`. | Each note has a title, a body, and a creation timestamp. Notes can be retrieved individually or as a list ordered by creation time. |
| Use a debounced `setTimeout` of 300ms to trigger search. | After the user stops typing, search results update within roughly a third of a second. Rapid typing does not produce intermediate searches. |
| The auth flow uses OAuth 2.0 PKCE with a 60-minute access token. | Users sign in through their identity provider. Sessions persist across app restarts and expire if unused for an extended period. |
| Spans are stored as `{start, end, classifier}` triples in a flat array. | Every classified region of input is bounded by a start and end position and is associated with exactly one classifier. |
| The parser emits `node_open`, then `text`, then `node_close`. | Consumers of the parser see a stream that opens a node, delivers its content, and closes it, in that order. |

When in doubt: *if this feature were rewritten with completely different code, would this requirement still hold?* If no, it's implementation.

There's one narrow exception. When a feature's *purpose* is to expose an external contract — a public API, a wire protocol, a file format, a CLI surface — then that contract IS the observable behavior, and describing its shape belongs in the spec. The test still holds: external consumers can observe it. Internal protocols between your own components don't qualify.

### Don't trade precision for vagueness

"No implementation" doesn't mean "fuzzy." A spec should be richly, specifically behavioral. If you find yourself softening a requirement to avoid implementation language, you've taken a wrong turn — reach instead for a more precise description of the observable behavior. "Search is fast" is not a spec; "search results appear within roughly a third of a second after the user stops typing" is a spec. The first is hand-waving, the second is observable.

### Structure as commitment, fields as open questions

Sometimes you need to commit to *that* a thing has internal structure without committing to *what* its structure is. This is a legitimate move and often the right one.

"Every ingredient is a structured item" is a behavioral commitment: the recipe view can address each ingredient as a unit, anchor a reference to it, ask about it in chat. Whether an ingredient has fields `quantity`, `unit`, `name`, `preparation`, or some other schema is a separate question that doesn't have to be answered to make the rest of the spec work.

When you take this move, put the specific fields in *Open questions*, not buried in the body. A reader should see: structure is the commitment; the specific shape is still open.

Don't reach for this as an escape hatch when you actually do know the shape. It's a way of saying "we agree this has structure" when committing further would be either speculation or implementation leak — not a way of dodging concreteness.

## Workflow

Work **depth-first**: one feature at a time. Ask, write, move on. Earlier specs inform later questions, and you usually don't know what's worth asking until you're inside the feature.

### 1. Read what's there

Read everything the user has put in front of you: the prompt, any files they reference, and obviously relevant things in the working directory (README, an existing `specs/`, CLAUDE.md or AGENTS.md, design notes). Read what's visible and stop — no fishing expeditions.

If `specs/` already exists, treat its contents as authoritative context. Don't overwrite anything without asking.

### 2. Confirm the feature list and propose a sequence

List the features as you understand them and confirm with the user before starting. This catches misinterpretation cheaply. While you're there:

- Flag features that feel underspecified, or are really two features in one trench coat.
- Propose a `core.md` if you see shared concepts across multiple features (a data model, a sync architecture, a shared abstraction, a cross-cutting constraint). Don't force it — only if it earns its place. See "When a core.md is worth it" below.
- Suggest an order. Specs with no dependencies first; specs that build on others later. The `core.md`, if there is one, goes first.

If the feature list itself is ambiguous in a way that affects decomposition — *is X really one feature or two? does feature Y collapse into feature Z?* — ask scope questions now, before sequencing. These are distinct from per-feature clarifying questions (which come in step 3). Scope questions resolve **what specs exist**; clarifying questions resolve **what each spec contains**. Getting the decomposition wrong is expensive to undo later, so it's worth a moment up front.

Wait for confirmation before proceeding.

### 3. For each feature, in sequence

For the current feature:

1. State which feature you're working on and briefly what you understand so far.
2. Ask clarifying questions — see "Asking good questions" below.
3. Wait for answers.
4. Write the spec to `specs/<kebab-case-feature-name>.md` using the template.
5. Note in one or two sentences what you wrote and what's next. Don't recap the spec — the file is right there.
6. Move on.

### 4. Write the INDEX

When all features are specced, write `specs/INDEX.md`. See the INDEX template below.

## Handling cascading changes

Spec'ing a later feature will sometimes reveal that an earlier spec is wrong, incomplete, or scoped at the wrong level. This is normal — depth-first work is one of the ways you find these things. Don't suppress it; treat it as the workflow earning its keep.

When you notice a cascade:

1. **Flag it in prose before changing any files.** Say what you noticed, what spec is affected, what the change is, and why. The user should know the cascade is happening before files start moving. Don't silently edit earlier specs.
2. **Make the change as an edit, not a rewrite.** Preserve everything that was right; touch only what needs to change.
3. **Continue with the current feature.** Don't context-switch fully back to the earlier work — finish what triggered the cascade, then present everything together.
4. **Present the affected files together.** When you next show output, include both the changed earlier spec and the new one, so the cascade is visible in a single view.

If the change is substantial — the earlier spec's basic shape was wrong, not just a missing requirement — pause and confirm with the user before making it. Small additions (one new requirement, one new edge case) don't need explicit sign-off as long as you flag them.

**Example.** While spec'ing recipes, you realize the user wants to highlight two ingredients at once and ask about substitutions. That's a property of anchored references in general, not a recipe-specific thing — references need to support multi-region anchors. That's a change to core, not to recipes. The flag in prose looks like:

> Your multi-region answer is a small core change, not a recipe-specific thing. Multi-region anchoring is a property of references themselves — it should apply to any entity kind. I'm going to update core requirement 4 to allow "one or more" addressable sub-regions and add a corresponding edge case. Flagging this explicitly before making the edit.

Then make the edits to core, write the recipe spec, present both. The user can see exactly what shifted and where.

## Asking good questions

This is where the skill earns its keep. A bad question wastes the user's time on something already answered or trivially obvious. A good question surfaces a real ambiguity whose resolution changes what gets written.

Heuristics:

- **Don't ask what's already there.** If the description says "users can tag notes with colors," don't ask "should notes be taggable?"
- **Prefer questions where each possible answer changes the spec.** If the spec is the same regardless, the question doesn't matter.
- **Edges and failures are fertile ground.** "What happens if the network is offline?" "What if two clients edit the same record at once?" "What's the maximum size?" "What if it's empty?"
- **Boundaries between features are often where ambiguity lives.** "Does search own the highlighting, or does each result type render its own?"
- **Acceptance criteria surface hidden requirements.** "How would you know this is working from the outside?" often elicits requirements the user hadn't articulated.
- **Two to five questions per feature is the right ballpark.** Many more than that and either you're over-asking or the feature is actually multiple features.

If a feature is genuinely clear from context, write the spec and move on. Don't ask questions for the sake of looking thorough.

## Spec template

Each `specs/<feature>.md` follows this structure. Omit sections that don't apply rather than padding them.

```markdown
# <Feature Name>

## Summary
<One short paragraph: what the feature is and why it exists.>

## User-facing behavior
<Walk through what someone using the feature observes. Be concrete and specific. If there are distinct flows or modes, cover each.>

## Behavioral requirements
<Numbered list. Each item is an observable, testable statement about how the feature behaves. Precise — but no code structure, libraries, or internal data shapes.>

1. ...
2. ...

## External interface
<Only include if the feature exposes a contract to external consumers — a public API, a wire protocol, a file format, a CLI surface. Describe the contract at the level a consumer sees it. Skip otherwise: internal interfaces between your own components are implementation.>

## Edge cases & error behavior
<What happens at the boundaries: empty input, oversized input, conflicting input, offline, partial failure, malformed data. What does the user see when things go wrong?>

## Acceptance criteria
<Checklist of testable conditions that, taken together, mean the feature is done. Each one observable from outside.>

- [ ] ...
- [ ] ...

## Dependencies
<Specs this feature builds on, and specs that build on it. Use relative links.>

- Depends on: [core](./core.md), [other-feature](./other-feature.md)
- Depended on by: [downstream-feature](./downstream-feature.md)

## Open questions
<Anything still unresolved. Better to leave a question here than silently decide it during implementation.>

## Out of scope
<Explicit non-goals. High-value section — it prevents scope creep and frees implementers to make local decisions without worrying they're missing something.>
```

## INDEX template

```markdown
# <Project Name> — Feature Specs

<One-paragraph project summary.>

## Specs

- [core](./core.md) — <one-line description>
- [feature-a](./feature-a.md) — <one-line description>
- [feature-b](./feature-b.md) — <one-line description>

## Dependencies

<Indented list or a Mermaid graph showing which specs depend on which.>

## Open cross-cutting questions

<Questions that affect multiple specs and remain unresolved.>
```

## When a `core.md` is worth it

Create one when:

- Multiple features depend on the same data model, conceptual model, or shared abstraction.
- The same cross-cutting constraints apply across many features (offline-first, single-user, real-time, eventually-consistent).
- There's a shared lifecycle (auth, sync, error handling) that's not a feature itself but underlies several.

Don't create one just because the project is large. If features genuinely stand on their own, skip it.

## Updating existing specs

If `specs/` already exists when the skill triggers, treat its contents as the starting point. Don't overwrite without asking. When the user comes in with a new feature list:

- Add specs for new features, leaving existing ones alone.
- Update specs the user explicitly asks you to revisit.
- Flag inconsistencies between the new feature list and existing specs — they often signal something has shifted in the user's understanding.

The `INDEX.md` should be regenerated each time so it stays current.

## A worked example

Here's a finished small spec for a feature you might find in a notes app. This is the level of precision and the kind of structure to aim for.

```markdown
# Favoriting

## Summary
Users can mark any note as a favorite. Favorited notes are visually distinguished and can be filtered to or quickly retrieved.

## User-facing behavior
A note shows a star control in its header. Tapping the star toggles its favorite state — filled when favorited, outlined when not. The state change is immediate and persists across app restarts and across the user's devices. From the main note list, a filter labeled "Favorites" shows only favorited notes.

## Behavioral requirements
1. Every note has a binary favorite state. The default is not favorited.
2. The favorite state of a note can be toggled from the note's header.
3. Toggling is immediate from the user's perspective; the visual state updates without perceptible delay.
4. The favorite state persists across app restarts.
5. The favorite state syncs across all devices for the same user. On conflict, the most recent change wins.
6. The note list supports filtering to favorited notes only.
7. Filtering preserves the current sort order of the list.

## Edge cases & error behavior
- If sync fails while toggling, the local state updates and is queued for retry. The user sees no error.
- A note deleted while favorited is removed from the favorites filter view without special handling.

## Acceptance criteria
- [ ] A user can favorite and unfavorite a note from its header.
- [ ] The favorite state survives an app restart.
- [ ] The favorite state propagates to another device within the normal sync window.
- [ ] The favorites filter shows exactly the favorited notes.
- [ ] Two devices toggling the same note converge to a single state.

## Dependencies
- Depends on: [core](./core.md) — note model, sync

## Open questions
- Should favoriting also be available from the list view, or only from inside a note?

## Out of scope
- Categorizing or tagging beyond a single binary favorite.
- Sharing or exporting the favorites list.
```

Notice what's not there: no mention of a database column, no API endpoint, no state management library, no specific sync protocol. The spec would still be correct if the implementation were SQLite + CRDTs or a Postgres + last-write-wins server or anything else. That's the property to aim for.
