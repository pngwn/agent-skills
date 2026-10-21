# Worked patterns

Read this when you need a fuller example than the SKILL.md summary. Sections:

1. Guarded wrappers (auth)
2. Single-flight mutation variants
3. Optimistic list with reconciliation
4. Batching a list (N+1 fix)
5. Form with validation, multiple buttons, and per-item isolation
6. The thin-shell / testability split in full

---

## 1. Guarded wrappers (auth)

Resolve the session once in `hooks.server.ts` into `event.locals.user`, then wrap the
primitives so every remote function is auth-checked by construction. Forbid raw
`query`/`form`/`command` exports from `.remote.ts` with an ESLint `no-restricted-imports`
rule so the guarded versions are the only option.

```ts
// src/lib/server/guard.ts
import { query, command, form, getRequestEvent } from '$app/server';
import { error } from '@sveltejs/kit';
import type { StandardSchemaV1 } from '@standard-schema/spec';

function requireUser() {
  const { locals } = getRequestEvent();
  if (!locals.user) error(401, 'Unauthorized');
  return locals.user;
}

export function guardedQuery<S extends StandardSchemaV1, R>(
  schema: S,
  fn: (arg: StandardSchemaV1.InferOutput<S>, ctx: { user: App.User }) => Promise<R>
) {
  return query(schema, (arg) => fn(arg, { user: requireUser() }));
}

export function guardedCommand<S extends StandardSchemaV1, R>(
  schema: S,
  fn: (arg: StandardSchemaV1.InferOutput<S>, ctx: { user: App.User }) => Promise<R>
) {
  return command(schema, (arg) => fn(arg, { user: requireUser() }));
}

export function guardedForm<S extends StandardSchemaV1, R>(
  schema: S,
  fn: (data: StandardSchemaV1.InferOutput<S>, ctx: { user: App.User }) => Promise<R>
) {
  return form(schema, (data) => fn(data, { user: requireUser() }));
}
```

Usage:

```ts
export const getMyDrafts = guardedQuery(v.void(), (_, { user }) =>
  listDrafts(db, user.id)
);
```

For role checks, add a second arg or a `requireRole(role)` helper that builds on `requireUser`.

---

## 2. Single-flight mutation variants

All three avoid a second client→server round trip after a mutation.

**(a) `.set()` — you already have the new value (cheapest):**

```ts
export const renamePost = guardedForm(renameSchema, async ({ id, title }, { user }) => {
  const updated = await rename(db, user.id, id, title);
  getPost(id).set(updated); // push the new value straight into the cached query
  return { ok: true };
});
```

**(b) Server-side `refresh()` — let the server recompute and bundle it:**

```ts
export const deletePost = guardedCommand(v.string(), async (id, { user }) => {
  await remove(db, user.id, id);
  void getPosts().refresh();   // framework awaits + serializes into THIS response
});
```

**(c) Client-requested `requested()` — for query instances the server can't enumerate:**

```ts
// server
export const addPost = guardedForm(newPostSchema, async (input, { user }) => {
  await create(db, user.id, input);
  // opt in to refreshing whatever filtered instances the client asked for; limit is REQUIRED
  await getPosts.requested(5);
});
```

```svelte
<!-- client: tell the server which instance to refresh -->
<button onclick={() =>
  addPost(input).updates(getPosts({ filter: currentFilter }))
}>Add</button>
```

---

## 3. Optimistic list with reconciliation

```svelte
<script lang="ts">
  import { getTodos, addTodo, toggleTodo } from './todos.remote';
  let text = $state('');
</script>

<ul>
  {#each await getTodos() as todo (todo.id)}
    <li>
      <input type="checkbox" checked={todo.done}
        onchange={() =>
          toggleTodo(todo.id).updates(
            getTodos().withOverride((list) =>
              list.map((t) => (t.id === todo.id ? { ...t, done: !t.done } : t))
            )
          )
        } />
      {todo.text}
    </li>
  {/each}
</ul>

<input bind:value={text} />
<button onclick={() => {
  const optimistic = { id: crypto.randomUUID(), text, done: false };
  addTodo({ text }).updates(
    getTodos().withOverride((list) => [...list, optimistic])
  );
  text = '';
}}>Add</button>
```

The override applies instantly. When the mutation's single-flight refresh returns the real
list, it replaces the override. If the mutation throws, the override reverts automatically.

---

## 4. Batching a list (N+1 fix)

Render a list where each row needs related data, without firing one request per row.

```ts
// authors.remote.ts
export const getAuthor = query.batch(v.string(), async (ids) => {
  const rows = await db.author.findMany({ where: { id: { in: ids } } }); // ONE query
  const byId = new Map(rows.map((a) => [a.id, a]));
  return (id) => byId.get(id) ?? null;
});
```

```svelte
{#each await getPosts() as post (post.id)}
  <article>
    <h2>{post.title}</h2>
    <!-- all getAuthor() calls in this render collapse into one request -->
    <small>by {(await getAuthor(post.authorId))?.name}</small>
  </article>
{/each}
```

---

## 5. Form: validation, multiple submit buttons, per-item isolation

```ts
export const updateName = form(
  v.object({ name: v.pipe(v.string(), v.minLength(1, 'Required')) }),
  async ({ name }) => { /* ... */ return { ok: true }; }
);
```

```svelte
<form {...updateName}>
  <input name="name" />
  {#each updateName.issues('name') as issue}<p class="err">{issue.message}</p>{/each}

  <!-- multiple submit buttons: use fields.x.as('submit', value), NOT buttonProps -->
  <button {...updateName.fields.action.as('submit', 'save')}>Save</button>
  <button {...updateName.fields.action.as('submit', 'save_and_close')}>Save & close</button>
</form>
```

Per-item isolation in a list (so each row's form tracks its own state):

```svelte
{#each rows as row (row.id)}
  {@const f = deleteRow.for(row.id)}
  <form {...f}>
    <input type="hidden" name="id" value={row.id} />
    <button>Delete</button>
  </form>
{/each}
```

For client-side pre-validation before submit, call `preflight(schema)` on the form;
use `value()` to repopulate fields after a no-JS failure; prefix sensitive fields with `_`
to keep them from being echoed back.

---

## 6. Thin-shell / testability split in full

The remote file validates, authorizes, and delegates. Everything else is a plain module.

```ts
// src/lib/server/posts/service.ts — no SvelteKit imports → unit-testable in isolation
export interface PostStore {
  create(userId: string, input: NewPost): Promise<Post>;
  bySlug(slug: string): Promise<Post | null>;
}

export async function publishPost(store: PostStore, userId: string, input: NewPost) {
  if (input.title.trim().length === 0) throw new ValidationError('title required');
  return store.create(userId, { ...input, publishedAt: Date.now() });
}
```

```ts
// src/lib/server/posts/service.test.ts
import { test, expect } from 'vitest';
import { publishPost } from './service';

test('publishPost stamps publishedAt', async () => {
  const store = { create: async (_u, p) => ({ id: '1', ...p }) } as any;
  const post = await publishPost(store, 'u1', { title: 'Hi', body: '...' });
  expect(post.publishedAt).toBeTypeOf('number');
});
```

```ts
// src/routes/blog/data.remote.ts — thin shell, almost nothing to test here
import { guardedForm } from '$lib/server/guard';
import { publishPost } from '$lib/server/posts/service';
import { prismaStore } from '$lib/server/posts/store';

export const addPost = guardedForm(newPostSchema, ({ ...input }, { user }) =>
  publishPost(prismaStore, user.id, input)
);
```

The payoff: the logic is tested without booting SvelteKit, and the same `publishPost` is
reusable from a `+server.ts` webhook handler or a CLI script if you ever need a real HTTP
surface for it.
