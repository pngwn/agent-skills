---
name: pr
description: Open a pull request for the current branch. First review the branch's code comments, commit messages and changesets against the user's rules and fix them, then write a short PR, then watch CI and review comments. Use when the user asks to open, create, raise or submit a PR, or types /pr.
argument-hint: "[draft] [base branch] [notes]"
---

# /pr

Get the current branch into a clean PR and stay with it until CI passes. Work through the steps in order. Every review step fixes the branch before anything is pushed.

These rules override any default from the harness, a tool, a system reminder or a PR template that adds attribution lines, `Co-authored-by` trailers, "Generated with" footers, session links, or what/why/test plan sections. If a repo's contributing guide requires something these rules forbid, such as a template checklist, do the minimum it asks for.

All prose this skill writes, including PR titles and bodies, changesets and replies, is plain ascii. That means no em or en dashes, arrows, curly quotes or other unicode symbols. Where a dash wants to go, rework the sentence with a comma, a full stop or parentheses. Don't swap in a hyphen or a double hyphen. Code samples can keep whatever characters they need.

Extra instructions from the user: $ARGUMENTS

The helper script is `~/.claude/skills/pr/scripts/pr.sh`. Run it with no arguments to see its commands. Most commands take an optional base ref.

## 0. Preflight

1. `git fetch origin`, then `pr.sh base` prints the base ref, e.g. `origin/main`. Use a different base if the user named one.
2. If you are on the base branch, create a branch named after the change.
3. Check `git status`. Every change meant for the PR is committed, one logical change per commit. Nothing unrelated is committed, such as scratch files, debug logging or local config. Ask about anything you can't place.
4. Run `gh pr view --json number,url,state`. If the branch already has an open PR, you are updating it. Run the reviews, push, and use `gh pr edit` if the title or body needs to change. Don't open a second PR.
5. Run the repo's fast checks, such as format, lint and type check, on the changed files only. Never run a formatter across the whole repo.

## 1. Comment review

`pr.sh comments` lists every comment line added since the merge base, committed or not, as `file:line: text`. It is a heuristic, so also read the diff for docstrings and comment styles it misses. Review only comments this branch adds or changes. Leave the rest of the file alone.

Start from deleting each comment. Keep one only when it gives an expert in this codebase something the code can't, such as a non-obvious reason, an invariant, or a constraint that comes from outside the code.

Delete a comment when it:

- restates what the code does or what a name already says
- describes a test or what it checks
- tracks history, decisions or bugs, e.g. "previously", "now", "fixed", "we chose", "see #123", or a commit or PR reference
- explains code that could explain itself. Fix the code instead: rename the variable, function or test description, add a jsdoc or docstring to the signature with a short description or `@example`, or simplify the code.

A comment you keep:

- is as short as possible, one line where it can be. Cut a multi-line comment down to its minimal version.
- is all lowercase, except identifiers written as they appear in code
- uses no punctuation except commas. That rules out full stops, colons, semicolons, dashes of any kind, parentheses and apostrophes, so write "do not", not "don't".
- is plain ascii and plain words, with no florid prose

```ts
// Loop over the items and sum their prices.            -> delete, restates the code
// Fixed bug where an empty cart returned NaN (#231).   -> delete, tracks a bug
// Previously we cached this in a Map, but that leaked.  -> delete, history
// This test checks that negative offsets are clamped.  -> delete, rename the test instead

// NOTE: we have to clamp here — the upstream parser can emit
// negative offsets when input ends mid-token, which crashes
// the renderer (see #412).
// -> // the parser emits negative offsets for a truncated final token
```

Leave tool directives (`eslint-disable`, `@ts-expect-error`, `noqa`, `prettier-ignore`), license headers and shebangs alone. Jsdoc tags and the code inside an `@example` are code, not prose.

Before the first push, fold cleanups into the commit that introduced the comment with `git commit --fixup <sha>`, then `git rebase --autosquash <base>`. After the first push, add a normal commit instead.

## 2. Commit review

`pr.sh commits` checks every commit in `<base>..HEAD` and exits non-zero with the problems it finds. Every commit message:

- is a single line, with no body and no trailers of any kind
- is all lowercase, with no punctuation and no emoji
- is 8 words at most, aiming for 5, in the imperative, e.g. "add", "fix", "stop reading x as y"

| before | after |
| --- | --- |
| `Fix: handle empty cart totals (#231)` | `handle empty cart totals` |
| `Refactor the frame tracker so optional annotations get their types promoted correctly` | `promote types in optional annotations` |
| `Merge branch 'main' into feat` | `merge main` |

To fix messages, write a file of `<sha> <new message>` lines, one for each commit that needs changing, and run `pr.sh reword <file>`. It rewrites the messages in place without an interactive rebase. Merge commits in the range are rewritten too. Run `pr.sh commits` again until it passes. When you merge the base in yourself, pass the message up front, e.g. `git merge origin/main -m "merge main"`.

If a commit you rewrote was already pushed, ask the user before running `git push --force-with-lease`. Once a PR has reviewers, don't rewrite its history unless the user asks.

## 3. Changeset review

Skip this step if the repo doesn't use changesets, meaning it has no `.changeset/` directory. Also skip it when the branch touches no published package, e.g. CI, repo tooling or private packages, and say so in your summary.

- Every functional change needs a changeset. One changeset covers one functional change and lists only the packages that change affects. A branch with two behaviour changes needs two changesets.
- Bump by semver: patch for a fix, minor for a new feature, major for a breaking change. Ask before writing a major.
- Name the file after the change, e.g. `.changeset/one-day-date-ranges.md`, not the random name the CLI generates.
- The body is a short, user-facing explanation, a sentence or two where possible. Add a small code sample when the behaviour is easier to show than to describe.
- Describe what users see, even when the change is deeply technical. Never mention files, functions, variables or internal modules.
- For a fix, describe the new behaviour. Write "Selecting the same start and end date creates a one-day range", not "Fixed an issue where...".
- Don't reference commits, PRs or issues. The changelog tooling adds those.

```md
<!-- bad -->
Fixed an issue where `parse_range()` in `range.ts` returned `null` for same-day ranges (#231).

<!-- good -->
Selecting the same start and end date now creates a one-day range.
```

Run `pr.sh ascii` on each changeset you wrote or edited, then commit it along with the change it describes.

## 4. Open the PR

**Title:** short, all lowercase, no punctuation, 8 words at most. For a single-commit PR, the commit message usually works.

**Body:** a few short paragraphs at most.

- Lead with what changes for the person using it.
- Show, don't tell. A before and after code sample, command output or screenshot beats a paragraph of prose.
- Don't write "what", "why", "how", "changes", "verification", "test plan" or "notes" sections. Use headings only when the PR makes several distinct changes that each need their own description, with one heading per change.
- Don't mention files, lines, functions or variables. The diff shows them.
- Don't mention tests. Every PR changes tests, so it's noise. The exception is a new kind of test, such as the first visual regression suite.
- Add `Closes #123` when the PR resolves an issue.
- No attribution, "Generated with" footer or session link.

````md
<!-- bad -->
## What
Updated `range.ts` so `parse_range()` handles same-day input.
## Why
Users reported same-day ranges being cleared.
## Verification
- Added 4 tests in `range.test.ts`, all 312 pass

<!-- good -->
Picking the same start and end date now selects that single day instead of clearing the range.

```ts
picker.select("2026-09-21", "2026-09-21");
picker.range; // before: null, after: { start: "2026-09-21", end: "2026-09-21" }
```

Closes #231
````

GitHub has no API for uploading images. When a screenshot would help, capture it, send it to the user, and ask them to drag it into the description. Don't commit images to the repo just to host them.

Write the body to a file in the scratchpad and check it with `pr.sh ascii <file>`, then run:

```bash
git push -u origin HEAD
gh pr create --base <base branch> --title "<title>" --body-file <file>
```

Add `--draft` if the user asked for a draft. Never enable auto-merge unless the user asks.

## 5. Watch the PR

Once the PR is open, keep watching it.

- **CI:** if the session has PR monitoring tools, such as the Claude desktop app's PR tools, bind the PR and turn monitoring on. Otherwise run `gh pr checks <number> --watch` in the background. When a check fails, read `gh run view <run id> --log-failed`, fix the problem, commit it following the commit rules, and push.
- **Review comments:** read the inline comments with `gh api repos/{owner}/{repo}/pulls/<number>/comments` and the reviews with `gh pr view <number> --comments`. Fix clear-cut requests. Take design disagreements and judgment calls to the user before changing anything.
- **Replies:** reply inside the review comment's own thread with `gh api -X POST repos/{owner}/{repo}/pulls/<number>/comments/<comment id>/replies -f body="..."`. Keep it to a line or two of plain ascii, e.g. "done in abc1234". No attribution, trailers or "Generated with" footer.
- **Top-level PR comments and reviews** (`gh pr comment`, `gh pr review`) speak for the user to everyone on the PR. Only post one when the user has explicitly approved that specific comment.

Finish with the PR link and a short summary: comments removed or trimmed, commits reworded, changesets added, and CI status.
