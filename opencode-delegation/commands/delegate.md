---
description: Hand ready-for-agent .scratch tickets to opencode one at a time, review each with Sonnet, send fixes back, then take the next ticket.
argument-hint: "[feature | ticket-path ...] [--max-rounds N]"
---

You are the dispatcher for an unattended overnight run. opencode does the implementation. You pick tickets, dispatch them, get them reviewed, send fixes back and keep a report. Do not implement tickets yourself. Never ask the user anything: nobody is watching. When something is ambiguous, pick the safe option (skip the ticket and note why).

Arguments: `$ARGUMENTS`. They can be feature folder names (`.scratch/<feature>`), ticket file paths, or nothing (meaning all features). `--max-rounds N` sets the maximum number of opencode rounds per ticket (default 3).

## 0. Preflight

- `git status --short`. If there are tracked changes, stop and report. Untracked files are fine.
- Record the branch and `RUN_BASE=$(git rev-parse HEAD)`.
- `LOGDIR="${TMPDIR:-/tmp}/opencode-delegation/$(basename "$PWD")/$(date +%Y%m%d-%H%M)"`. All logs go here, never inside the repo.
- `REPORT="$LOGDIR/report.md"`. Create it with a header that records the branch and `RUN_BASE`.

## 1. Build the queue

Read the frontmatter of every `.scratch/*/issues/*.md` in scope. The issue-tracker conventions are in `docs/agents/issue-tracker.md` when the repo has that file. A ticket is eligible when all of these hold:

- `status: open`
- `labels` contains `ready-for-agent`
- `assignee` is null/empty or `opencode`
- it is not a map (`wayfinder:map`) and not a spec/PRD parent. A spec/PRD parent is a ticket whose own file says it is a spec or PRD, or one that other tickets name as their parent or spec.

Order the queue by feature, then by numeric id. Before each dispatch, re-check `blocked_by`: every listed id in the same feature must be `closed` right now. Skip a blocked ticket for now and come back to it after each completed ticket. Write the initial queue into the report.

## 2. For each ticket

Let `T` be the ticket path, `ID` be `<feature>#<id>`, `BASE=$(git rev-parse HEAD)` and `LOG="$LOGDIR/<feature>-<id>.jsonl"`.

**Dispatch.** Run this with the Bash tool with `run_in_background: true`:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/oc-run.sh" "$LOG" --title "$ID" "<PROMPT>"
```

Then stop and wait for the completion notification. Do not poll or sleep. When it arrives, read the command's output (the `exit=… session=…` line plus the final message). Keep `SESSION`.

`<PROMPT>` (fill in the path):

> Implement the ticket at `<T>`. Read the ticket in full first. Then read `~/.agents/skills/implement/SKILL.md` with the read tool (it cannot be loaded through the skill tool) and follow it. Before writing any code, load the `tdd` skill with the skill tool and work red-green at the ticket's seams. While working, typecheck and run only the test files you touched or that cover the code you changed, using this repo's own typecheck and test commands (see its AGENTS.md/CLAUDE.md, or the project's config files when they are not documented). Run each affected package's full suite exactly once, at the end, just before committing; if it fails, fix and re-run only the failing files, then the full suite once more. Before committing, load the `code-review` skill with the skill tool, review your own diff and fix what it finds. Commit to the current branch.
> On this machine the built-in `grep` and `glob` tools fail (ripgrep is missing and cannot be extracted), and `rg` is not on PATH. Do not call them. Search with `git grep -n "<pattern>" -- <paths>` and list files with `git ls-files <pathspec>` through the shell tool.
> Think and write in English only, including after a context compaction; Thai appears only in UI strings and tests that already use it.
> No human is available during this run. Do not ask questions. Make reasonable decisions that stay inside the ticket's scope and the repo's AGENTS.md/CLAUDE.md rules. Do not implement tickets listed in `blocked_by` or other tickets.
> When done: set the ticket's `status: closed` and `assignee: opencode`, append a dated `## Notes` entry (what changed, tests run, any deviation), and include the ticket file in your commit.
> If you truly cannot finish, leave `status: open`, add a `## Notes` entry that explains the blocker, commit whatever work is safe, and stop.

**Review.** Launch the `opencode-delegation:ticket-reviewer` agent in the foreground with this prompt (fill in the ticket path, the commit and the log path): `Ticket: <T>. Base commit: <BASE>. Gate log: bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate-log.sh" "<LOG>"`

**Decide.**

- `PASS`: add a report row and continue to the next ticket.
- `FAIL` with rounds left: run the same background dispatch with `--session "$SESSION"` and this message: "Reviewer found the ticket incomplete. Fix exactly these points, re-run the affected tests, update the ticket Notes, commit:\n<FIX section verbatim>". Then review again against the same `BASE`.
- `FAIL` with no rounds left, or opencode exited non-zero twice in a row: give up on the ticket.
  - If the tree is dirty, run `git stash push -u -m "opencode-delegation <ID>"`.
  - Append this entry to the ticket: `## Notes\n- <date> opencode-delegation: gave up after N rounds — <unmet criteria>`. Set `labels` to swap `ready-for-agent` for `ready-for-human`.
  - Commit only that ticket file: `chore(<feature>): opencode-delegation gave up on <id>`.
  - Tickets blocked by this one stay skipped.

After each ticket, check that the working tree is clean before you dispatch the next one. If it is not clean, stash it as above and note that in the report.

## 3. Report

Append one row per ticket to `$REPORT`:

`| ID | PASS/GAVE-UP/SKIPPED | rounds | commits (BASE..HEAD short shas) | opencode session | one-line note |`

When the queue is empty (only blocked or ineligible tickets are left), add these sections:

- A "Still blocked / skipped" list with the reasons.
- A "Morning review" section with `git log --oneline RUN_BASE..HEAD`, the stash list, and how to inspect a run: `opencode -s <session>` or the `.jsonl` log.

Finish with a short summary and the report path.

Keep your own context small. Do not cat the logs. Rely on the script's compact output and the reviewer's verdict.
