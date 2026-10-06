---
description: Hand one .scratch feature to codex to implement all its tickets in parallel with the implement-spec skill, then review every ticket with Sonnet and send fixes back.
argument-hint: "<feature> [--max-rounds N]"
---

You are the dispatcher for an unattended run. codex orchestrates the whole feature itself with the `implement-spec` skill: it runs the tickets as a task graph, with parallel sub-agents in worktrees, and merges them into one integration branch. You start it, prove the result with your own gate runs, get every ticket reviewed, send fixes back and keep a report. Do not implement tickets yourself. Never ask the user anything: nobody is watching. When something is ambiguous, pick the safe option and note why.

Arguments: `$ARGUMENTS`. One feature folder name (`.scratch/<feature>`). `--max-rounds N` sets the maximum number of fix rounds after the first run (default 2).

## 0. Preflight

- `git status --short`. If there are tracked changes, stop and report. Untracked files are fine.
- If the current branch is `main` or `master`, create and check out `spec/<feature>`. The current branch is now the integration branch `BRANCH`. Record `RUN_BASE=$(git rev-parse HEAD)`.
- `LOGDIR="${TMPDIR:-/tmp}/codex-delegation/$(basename "$PWD")/$(date +%Y%m%d-%H%M)"`. All logs go here, never inside the repo. `LOG="$LOGDIR/<feature>.jsonl"`.
- `REPORT="$LOGDIR/report.md"`. Create it with a header that records `BRANCH` and `RUN_BASE`.
- Tickets are `.scratch/<feature>/issues/*.md`; the conventions are in `docs/agents/issue-tracker.md` when the repo has that file. The run covers every ticket whose status is `open` and whose labels contain `ready-for-agent`. Write that list into the report. If it is empty, stop and report.
- **Baseline gates.** Run this repo's own full typecheck and test commands for every package (see its AGENTS.md/CLAUDE.md, or the project's config files when they are not documented). For each command append to `$LOGDIR/gates-base.txt`: a `$ <command> (in <dir>)` line, then the part of the output that names each failure and the totals (at most 60 lines). Failures listed here existed before the run and are allowed later.

## 1. Dispatch

Run this with the Bash tool with `run_in_background: true`:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cx-run.sh" "$LOG" "<PROMPT>"
```

Then stop and wait for the completion notification. Do not poll or sleep: a feature takes hours. When it arrives, read the command's output (the `exit=… session=…` line plus the final message). Keep `SESSION`.

`<PROMPT>` (fill in `<feature>` and `<BRANCH>`):

> Implement every open `ready-for-agent` ticket in `.scratch/<feature>/issues/` for the spec in `.scratch/<feature>/`. Read `~/.agents/skills/implement-spec/SKILL.md` and follow it. Where it says to call the Skill tool with a skill name, read `~/.agents/skills/<name>/SKILL.md` and follow that instead; tell every sub-agent the same. The issue tracker is the local markdown tracker described in `docs/agents/issue-tracker.md`.
> The integration branch is `<BRANCH>`, already checked out in this directory. Do not create another one, do not open a PR and do not push. Put worktrees outside the repo.
> Each implementer, in its own branch and before it reports done: runs its package's full typecheck and test suite once, ticks every acceptance criterion it met (`[x]`), sets the ticket's status to `closed` and its assignee to `codex`, appends a dated `## Notes` entry (what changed, tests run, any deviation), and commits the ticket file with the work.
> Do not trust an implementer's "done" message. Before merging, check that its branch has a new commit and its worktree is clean; if not, resume it until it has.
> Merge every ticket into the integration branch with its own `git merge --no-ff`, with the subject `Merge ticket <NN>: <title>`, where `<NN>` is the ticket's file number. One merge commit per ticket, even when several finish together.
> When a ticket cannot be finished, leave its status `open`, add a `## Notes` entry that explains the blocker, do not start the tickets it blocks, and carry on with the rest.
> On this machine `rg` may be missing from PATH. If it is, search with `git grep -n "<pattern>" -- <paths>` and list files with `git ls-files <pathspec>`. Tell every sub-agent the same.
> Think and write in English only, including after a context compaction; Thai appears only in UI strings and tests that already use it.
> No human is available during this run. Do not ask questions. Make reasonable decisions that stay inside the tickets' scope and the repo's AGENTS.md/CLAUDE.md rules.

## 2. Gates

Check that the working tree is clean and `BRANCH` is checked out (if not: `git stash push -u -m "codex-delegation <feature>"`, check out `BRANCH`, note it in the report). Run the same commands as the baseline and write them the same way to `$LOGDIR/gates-final.txt`. A failure that is not in `gates-base.txt` is a new failure.

## 3. Review

For each ticket in the run, find its merge commit: `M=$(git log --merges --format=%H --grep="^Merge ticket <NN>:" "$RUN_BASE"..HEAD | tail -1)`.

- No merge commit, or status still `open`: the ticket is `NOT-DONE`. Do not review it.
- Otherwise launch the `codex-delegation:ticket-reviewer` agent with: `Ticket: <T>. Base commit: <M>^1. Head commit: <M>. Gate log: cat "$LOGDIR/gates-base.txt" "$LOGDIR/gates-final.txt" (the first file is the baseline from before the run; failures that are also in it are allowed).`

Launch all reviewers in one message so they run in parallel, in the foreground.

## 4. Decide

- Every reviewed ticket is `PASS` and there are no new gate failures: go to the report.
- Otherwise, with rounds left: run the same background dispatch with `--session "$SESSION"` and this message: "Review of the integration branch found problems. Fix exactly these points with one implementer sub-agent, directly on the integration branch, one commit per ticket with the subject `Fix ticket <NN>: …`. Re-run the affected packages' full suites, update each ticket's Notes and commit.\n<per ticket: its id and FIX section verbatim>\n<new gate failures: command and failure lines>". Tickets that are `NOT-DONE` are not sent back; codex already explained the blocker in their Notes.
  Then repeat step 2, and review only the tickets that failed, with `Head commit: HEAD` and this line added: "Other tickets were merged in this range. Judge only this ticket's criteria and skip the unrelated-files check."
- No rounds left, or codex exited non-zero twice in a row: give up on the failing tickets. For each one, set its status back to `open`, swap the label `ready-for-agent` for `ready-for-human`, and append `## Notes\n- <date> codex-delegation: gave up after N rounds — <unmet criteria>`. Commit only those ticket files: `chore(<feature>): codex-delegation gave up on <ids>`. Do the same label swap for `NOT-DONE` tickets, keeping codex's Notes.

## 5. Report

Append one row per ticket to `$REPORT`:

`| ID | PASS/GAVE-UP/NOT-DONE | fix rounds | merge commit (short sha) | one-line note |`

Then add these sections:

- "Gates": new failures still present, and the number of baseline failures.
- "Left over": `git worktree list` entries and `git branch --list` branches the run created and did not remove, and the stash list. Do not delete them.
- "Morning review": `git log --oneline --first-parent RUN_BASE..HEAD`, and how to inspect the run: `codex resume <SESSION>` or the `.jsonl` log.

Finish with a short summary and the report path.

Keep your own context small. Do not cat the run log. Rely on the script's compact output, the gate files and the reviewers' verdicts.
