---
name: sveltekit-remote-functions
description: >-
  Authoritative patterns for data fetching and mutations in SvelteKit using remote
  functions (query, form, command, prerender) and async SSR. Use this skill WHENEVER
  writing or modifying any SvelteKit code that reads or writes data — including loading
  data into a page or component, submitting a form, performing a mutation, fetching from
  a database or API on the server, or anything you might historically have done with a
  `load` function or a `+server.ts` endpoint. Default to remote functions for ALL
  internal app data flow. This skill covers how to write each kind, how to keep them
  testable, how to minimize round trips (batching, single-flight mutations, explicit
  refreshes), and optimistic UI. Assume all experimental flags are enabled.
---

# SvelteKit Remote Functions

Remote functions are the default data layer for this codebase. They are exported from
`.remote.ts` files, **always run on the server** (safe for DB access, secrets, and
privileged operations), and are callable from anywhere — during component render or in
response to user interaction. The client never sees their implementation; calls compile
to fetches against an internal, hidden endpoint.

This skill assumes async SSR is on, so `await`ed data resolves during server render and
is reused on hydration (no double-fetch, no flash).

## The decision rule (apply this every time)

**Default to a remote function for everything internal.** Reach for the alternatives
only in the specific exception cases below.

| Need | Use |
| --- | --- |
| Read dynamic data | `query` |
| Read many items in a list (avoid N+1) | `query.batch` |
| Real-time / streaming data into the app | `query.live` |
| Build-time / static data | `prerender` (a build-time query) |
| Write data (mutation) | `form` by default; `command` only when there is no form and JS is guaranteed |
| Top-of-tree auth guard / redirect before render | `load` in `+layout.server.ts` (or the `handle` hook) |

### When NOT to use a remote function — use `+server.ts` instead

Remote functions are an *internal* RPC mechanism: their URL is hidden, `url.pathname` is
always `/`, there are no `params` or `route.id`, and you generally **cannot set response
headers or control content type** (you can only set cookies, and only inside `form`/`command`).
So keep a `+server.ts` endpoint for anything that must be a real, addressable HTTP resource:

- **Webhooks** (Stripe, GitHub, etc.) — external services POST to a fixed, known URL.
- **OAuth callbacks** — the provider redirects to a known route.
- **Public REST/JSON APIs** and **non-browser clients** (mobile apps, CLIs, other services).
- **File downloads/uploads as raw responses**, custom `Content-Type`, custom headers, or header-bearing redirects.
- **SSE / WebSockets** to external clients (`query.live` covers in-app real-time only).
- **Static/desktop builds** (`adapter-static`, Tauri/Electron) — `query`/`form`/`command` need a server; only `prerender` works.

### When `load` still earns its place

Remote functions do **not** deprecate `load`. Architect so data fetching is decoupled
from routing, but still use `load` for: top-of-tree auth redirects/guards before any
component renders, page `data` you genuinely want typed through `$types`, and data shared
across many routes (session, global config). Do **not** put redirects/guards inside a
`query` — do them in `+layout.server.ts` or `handle`.

## Writing remote functions — the API

Put remote functions in `*.remote.ts` files. Co-locate route-specific ones next to the
route (`src/routes/blog/data.remote.ts`); put cross-cutting ones in `src/lib`
(`src/lib/remote/posts.remote.ts`). **Never** place them in `src/lib/server`. You cannot
export a plain schema from a `.remote.ts` file — keep shared schemas in a separate module.

Arguments cross the network, so the TypeScript signature is **not** a runtime guarantee.
**Always validate arguments with a Standard Schema** (Zod / Valibot / Arktype). A client
can send any JSON.

### `query` — read dynamic data

```ts
// src/routes/blog/data.remote.ts
import { query } from '$app/server';
import * as v from 'valibot';
import { getPostBySlug } from '$lib/server/posts'; // plain, testable logic

export const getPost = query(v.string(), async (slug) => {
  const post = await getPostBySlug(slug);
  if (!post) error(404, 'Not found');
  return post; // serialized with devalue — Date/Map/Set/custom types OK
});
```

```svelte
<script lang="ts">
  import { getPost } from './data.remote';
  let { slug }: { slug: string } = $props();
</script>

<!-- await resolves during SSR; reused on hydration -->
<h1>{(await getPost(slug)).title}</h1>
```

A `query` instance also exposes `.loading`, `.error`, `.current`, `.refresh()`, `.set()`,
and `.withOverride()`. Awaiting a query is only valid inside a **reactive context**
(template, `$derived`, `$effect`). For one-off imperative reads outside render, use
`getPost.run(slug)`.

### `query.batch` — solve N+1 for lists

When a list renders a per-item query, batch them: all calls in the same task collapse into
one request. The server gets an array of args and returns a `(arg, index) => result` resolver.

```ts
export const getAuthor = query.batch(v.string(), async (ids) => {
  const authors = await loadAuthors(ids);          // ONE query for all ids
  const byId = new Map(authors.map((a) => [a.id, a]));
  return (id) => byId.get(id);                      // resolver per call
});
```

### `query.live` — real-time

Backed by an async generator; auto-reconnects with backoff; exposes `connected` and
`reconnect()`; has no `refresh()` (it updates itself).

### `prerender` — build-time data

Same shape as `query` but invoked at build time and cached on CDN + the browser `Cache`
API. Supports `entries` and `dynamic: true`. Cannot be used on a page that itself sets
`export const prerender = true` (queries are dynamic).

### `form` — write data (default for mutations)

`form` is the default for mutations because it **works without JavaScript** and
progressively enhances. It returns an object you spread onto a `<form>`.

```ts
// src/routes/blog/data.remote.ts
import { form, getRequestEvent } from '$app/server';
import * as v from 'valibot';
import { createPost } from '$lib/server/posts';

export const addPost = form(
  v.object({ title: v.string(), body: v.string() }),
  async ({ title, body }) => {
    const { locals } = getRequestEvent();
    if (!locals.user) error(401);
    const post = await createPost(locals.user.id, title, body);

    // Single-flight: refresh sibling query in the SAME response (no extra round trip)
    getPosts().set(await getPosts.run());   // or: void getPosts().refresh();
    return { success: true, id: post.id };
  }
);
```

```svelte
<form {...addPost}>
  <input name="title" />
  <textarea name="body"></textarea>
  <button>Post</button>
</form>
```

Form helpers: `fields.x.as(type, value)` (for typed inputs and multiple submit buttons —
note `buttonProps` no longer exists), `issues()` / `allIssues()` for validation errors,
`validate()`, `preflight(schema)` for client-side pre-validation, `for(id)` to isolate a
form per list item, `value()` to repopulate after a no-JS failure, and `enhance()` for a
custom submit handler. Coercion is limited: prefix numeric fields with `n:` and boolean
checkboxes with `b:`. Dates are **not** coerced — send a UNIX timestamp. Prefix a field
with `_` (e.g. `_password`) so its value isn't echoed back on a failed no-JS submit.

### `command` — write data without a form

`command` mutates from anywhere (button handlers, drag/drop, toggles). It **requires JS**
and **cannot be called during render**. Prefer `form` whenever the action maps to a form,
because `form` degrades gracefully.

```ts
import { command } from '$app/server';
export const toggleLike = command(v.string(), async (postId) => {
  /* ... */
  void getPost(postId).refresh(); // single-flight refresh
});
```

```svelte
<button onclick={() => toggleLike(post.id)}>Like</button>
```

## Testability — the most important architectural habit

Remote functions are awkward to unit-test directly (they expect SvelteKit's server
internals). **So keep the wrapper thin and push all real logic into plain functions you
can import and test in isolation.** The `.remote.ts` file should do three things only:
validate input, check auth, and delegate.

```ts
// src/lib/server/posts.ts  — pure, fully testable, no SvelteKit imports
export async function createPost(db: Db, userId: string, input: NewPost) { /* ... */ }

// src/routes/blog/data.remote.ts — thin shell
export const addPost = form(newPostSchema, async (input) => {
  const { locals } = getRequestEvent();
  if (!locals.user) error(401);
  return createPost(db, locals.user.id, input);
});
```

Test `createPost` directly with a test DB/mock. The remote wrapper has so little logic
that an integration test (or type-checking) covers it. This separation also makes the same
logic reusable from a `+server.ts` endpoint or a script.

### Guarded wrappers for auth

There is no built-in auth. Resolve the session once in the `handle` hook into
`event.locals.user`, then enforce it inside every remote function. To avoid forgetting,
build `guardedQuery` / `guardedForm` / `guardedCommand` wrappers that perform the auth
check and inject `{ user, event }`, and forbid raw `query`/`form`/`command` exports from
`.remote.ts` via an ESLint rule. See `references/patterns.md` for the wrapper
implementation.

## Performance — minimize round trips

A mutation usually invalidates data. By default `form` re-runs **all** queries/loads
(a full-reload mimic) and `command` invalidates **nothing** — both are usually wrong and
both can cost a second round trip. Use **single-flight mutations**: refresh the affected
queries and return their new data in the *same* response. Prefer these in order:

1. **`.set(data)` when the handler already has the new value** — zero re-fetch.
   ```ts
   getPost(id).set(updatedPost);
   ```
2. **Server-side `void someQuery().refresh()`** inside the handler — the framework awaits
   it and bundles the result into the mutation response.
3. **Client-requested refresh** for instances the server can't enumerate (e.g. a filtered
   query): client calls `submit().updates(getPosts({ filter }))`; the server opts in with
   `requested(getPosts, limit)`. The `limit` is **required** (prevents client-driven DoS).

Other levers:
- **`query.batch`** for any per-item list query (see above) — the single biggest fix for request waterfalls.
- **Dedup is automatic:** identical query calls share one instance per request (server) and
  one cached instance while reactively in use (client). Don't hand-roll caching.
- **`prerender`** anything build-stable so it never hits the server at runtime.
- If you see a waterfall (component awaits an id, child awaits its detail), hoist to a single composite query or `query.batch` rather than nesting awaits.

## Optimistic UI

Apply an instant local override and let it **revert automatically on error**. Pass the
overridden query into the mutation's `.updates()` so the server's single-flight refresh
reconciles it.

```svelte
<script lang="ts">
  import { getTodos, addTodo } from './todos.remote';
</script>

{#each await getTodos() as todo}<li>{todo.text}</li>{/each}

<button onclick={() => {
  addTodo({ text }).updates(
    getTodos().withOverride((todos) => [...todos, { id: 'temp', text }])
  );
}}>Add</button>
```

Use **`.withOverride()`** (older posts may show `.override()` — that name is stale). The
override holds until the real refresh lands; if the mutation throws, it rolls back.

## Quick checklist before finishing any data code

- Is this internal app data/mutation? → remote function. External/addressable HTTP? → `+server.ts`.
- Are all arguments validated with a Standard Schema?
- Is auth checked inside the function (via a guarded wrapper)?
- Is the real logic in a plain, testable function with the remote file as a thin shell?
- For mutations: is it single-flight (`.set()` / server `refresh()` / `requested()`) rather than relying on default invalidation?
- For list reads: is it `query.batch` rather than N separate queries?
- Should this write be a `form` (works without JS) rather than a `command`?
- Does interactive mutation UI use `.withOverride()` for optimism?

See `references/patterns.md` for fuller worked examples (guarded wrappers, single-flight
variants, optimistic lists, batching).
