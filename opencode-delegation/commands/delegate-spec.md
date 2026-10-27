---
description: Hand one .scratch feature to opencode to implement all its tickets in parallel with the implement-spec skill, then review every ticket with Sonnet and send fixes back.
argument-hint: "<feature> [--max-rounds N]"
---

You are the dispatcher for an unattended run. opencode orchestrates the whole feature itself with the `implement-spec` skill: it runs the tickets as a task graph, with parallel sub-agents in worktrees, and merges them into one integration branch per repo. You start it, prove the result with your own gate runs, get every ticket reviewed, send fixes back and keep a report. Do not implement tickets yourself. Never ask the user anything: nobody is watching. When something is ambiguous, pick the safe option and note why.

Arguments: `$ARGUMENTS`. One feature folder name (`.scratch/<feature>`). `--max-rounds N` sets the maximum number of fix rounds after the first run (default 2).

## Repos

The current directory is the **workspace repo**: it holds `.scratch/` and every ticket file. Code may also live in **nested repos**: top-level directories with their own `.git` that the workspace repo ignores (`for d in */; do [ -e "$d.git" ] && git check-ignore -q "$d" && echo "${d%/}"; done`). `REPOS` is `.` followed by those directories. With no nested repos, `REPOS` is just `.` and every "per repo" step below runs once.

Run every git command against a repo with `git -C <repo>`. Each repo gets its own `BRANCH[<repo>]` and `RUN_BASE[<repo>]`.

## 0. Preflight

- For each repo in `REPOS`: `git -C <repo> status --short`. If any repo has tracked changes, stop and report. Untracked files are fine.
- For each repo: if its current branch is `main` or `master`, create and check out `spec/<feature>` there. Its current branch is now its integration branch `BRANCH[<repo>]`. Record `RUN_BASE[<repo>]=$(git -C <repo> rev-parse HEAD)`.
- `OC_REPOS` is the space-separated list `<repo>=<RUN_BASE[<repo>]>` for every repo (for example `.=1a2b3c backend=4d5e6f frontend=7a8b9c`).
- `LOGDIR="${TMPDIR:-/tmp}/opencode-delegation/$(basename "$PWD")/$(date +%Y%m%d-%H%M)"`. All logs go here, never inside a repo. `LOG="$LOGDIR/<feature>.jsonl"`.
- `REPORT="$LOGDIR/report.md"`. Create it with a header that records `BRANCH` and `RUN_BASE` for every repo.
- Tickets are `.scratch/<feature>/issues/*.md` in the workspace repo; the conventions are in `docs/agents/issue-tracker.md` when the repo has that file. The run covers every ticket whose status is `open` and whose labels contain `ready-for-agent`. When the tracker doc maps these roles to one `**Status:**` value (for example `ready-for-agent` = open and ready, `closed` = done), follow the tracker doc, and put its vocabulary in the opencode prompt. Write that list into the report. If it is empty, stop and report.
- **Baseline gates.** Run each repo's own full typecheck and test commands for every package (see the workspace and repo AGENTS.md/CLAUDE.md, or the project's config files when they are not documented). Run at most two at once (typechecks together, then the test suites together): four parallel runs cause timeouts that look like failures. A test that times out is rerun alone before it goes into the baseline. For each command append to `$LOGDIR/gates-base.txt`: a `$ <command> (in <dir>)` line, then the part of the output that names each failure and the totals (at most 60 lines). Failures listed here existed before the run and are allowed later.

## 1. Dispatch

Run this with the Bash tool with `run_in_background: true`:

```
OC_REPOS="$OC_REPOS" bash "${CLAUDE_PLUGIN_ROOT}/scripts/oc-run.sh" "$LOG" --title "<feature> spec" "<PROMPT>"
```

Then stop and wait for the completion notification. Do not poll or sleep: a feature takes hours. When it arrives, read the command's output (the `exit=… session=…` line, the final message and the `state:` line, which shows worktrees and merges per repo). Keep `SESSION`.

The exit code is not proof of anything: a run can exit 0 after one sentence, and exit 1 while the work carries on. Decide from `state:` and git (`git -C <repo> worktree list` and `git -C <repo> log --merges "$RUN_BASE[<repo>]"..HEAD` per repo, the tickets' `Status:` lines):
- `opencode_procs` above 0, or a worktree under the temp dir with a recent commit in any repo: work is still running. Wait with a background `until` loop on `ps`, and do not resume.
- Tickets still open, `opencode_procs=0` and no worktree in any repo: the orchestrator stopped early. Resume once with `--session "$SESSION"`; this does not use up a fix round. Open the message with the state you saw, and tell it to run sub-agents in the foreground and not to end its turn before every ticket is merged or blocked.

`<PROMPT>` (fill in `<feature>` and the repo lines). With only the workspace repo, leave out the two sentences marked *(nested repos only)*:

> Implement every open `ready-for-agent` ticket in `.scratch/<feature>/issues/` for the spec in `.scratch/<feature>/`. Read `~/.agents/skills/implement-spec/SKILL.md` with the read tool (it cannot be loaded through the skill tool) and follow it. The issue tracker is the local markdown tracker described in `docs/agents/issue-tracker.md`.
> The code lives in these git repos, each with its integration branch already checked out: `<repo>` on `<BRANCH[repo]>` (one line per repo). Do not create other integration branches, do not open a PR and do not push. Put worktrees outside every repo. *(nested repos only)* The nested repos are separate git repos that the workspace repo ignores: a ticket's code goes in the repo that holds the files it changes, and a ticket that spans several repos gets one worktree and one branch in each, with the same branch name.
> Each implementer, in its own branch and before it reports done: runs its package's full typecheck and test suite once, ticks every acceptance criterion it met (`[x]`), sets the ticket's status to `closed` and its assignee to `opencode`, appends a dated `## Notes` entry (what changed, tests run, any deviation), and commits its work. A ticket file whose code is in the workspace repo is committed with the work. *(nested repos only)* A ticket file whose code is only in nested repos is edited in place in the workspace checkout and not committed by the implementer; after merging that ticket's code, you commit the ticket file on the workspace integration branch with the subject `Close ticket <NN>: <title>`.
> Run every sub-agent in the foreground and wait for it. Do not end your turn while a ticket is neither merged nor blocked.
> Do not trust an implementer's "done" message. Before merging, check that each of its branches has a new commit and each of its worktrees is clean; if not, resume it until it has.
> Merge every ticket into the integration branch of each repo it changed with its own `git merge --no-ff`, with the subject `Merge ticket <NN>: <title>`, where `<NN>` is the ticket's file number. One merge commit per ticket per repo, even when several finish together.
> When a ticket cannot be finished, leave its status `open`, add a `## Notes` entry that explains the blocker, do not start the tickets it blocks, and carry on with the rest.
> On this machine the built-in `grep` and `glob` tools fail (ripgrep is missing and cannot be extracted), and `rg` is not on PATH. Do not call them. Search with `git grep -n "<pattern>" -- <paths>` and list files with `git ls-files <pathspec>` through the shell tool (inside the repo that holds the files). Tell every sub-agent the same.
> Think and write in English only, including after a context compaction; Thai appears only in UI strings and tests that already use it.
> No human is available during this run. Do not ask questions. Make reasonable decisions that stay inside the tickets' scope and the repo's AGENTS.md/CLAUDE.md rules.

## 2. Gates

For each repo, check that its working tree is clean and `BRANCH[<repo>]` is checked out (if not: `git -C <repo> stash push -u -m "opencode-delegation <feature>"`, check out its branch, note it in the report). Run the same commands as the baseline and write them the same way to `$LOGDIR/gates-final.txt`. A failure that is not in `gates-base.txt` is a new failure.

## 3. Review

For each ticket in the run and each repo, find its merge commit: `M=$(git -C <repo> log --merges --format=%H --grep="^Merge ticket <NN>:" "$RUN_BASE[<repo>]"..HEAD | tail -1)`. The ticket's **changes** are the repos where `M` exists, plus the workspace repo's `Close ticket <NN>:` commit when there is one.

- No merge commit in any repo, or status still `open`: the ticket is `NOT-DONE`. Do not review it.
- Otherwise launch the `opencode-delegation:ticket-reviewer` agent with: `Ticket: <T>. Changes: <one line per repo: Repo <repo>, base <M>^1, head <M>> (for a Close ticket commit C: Repo ., base <C>^1, head <C>). Gate log: cat "$LOGDIR/gates-base.txt" "$LOGDIR/gates-final.txt" (the first file is the baseline from before the run; failures that are also in it are allowed).`

Launch all reviewers in one message so they run in parallel, in the foreground.

## 4. Decide

- Every reviewed ticket is `PASS` and there are no new gate failures: go to the report.
- Otherwise, with rounds left: run the same background dispatch with `--session "$SESSION"` and this message: "Review of the integration branches found problems. Fix exactly these points with one implementer sub-agent, directly on the integration branch of each affected repo, one commit per ticket per repo with the subject `Fix ticket <NN>: …`. Re-run the affected packages' full suites, update each ticket's Notes and commit them in the workspace repo.\n<per ticket: its id and FIX section verbatim>\n<new gate failures: command, repo and failure lines>". Tickets that are `NOT-DONE` are not sent back; opencode already explained the blocker in their Notes.
  Then repeat step 2, and review only the tickets that failed, with each change's head set to `HEAD` of its repo and this line added: "Other tickets were merged in this range. Judge only this ticket's criteria and skip the unrelated-files check."
- No rounds left, or opencode exited non-zero twice in a row: give up on the failing tickets. For each one, set its status back to `open`, swap the label `ready-for-agent` for `ready-for-human`, and append `## Notes\n- <date> opencode-delegation: gave up after N rounds — <unmet criteria>`. Commit only those ticket files in the workspace repo: `chore(<feature>): opencode-delegation gave up on <ids>`. Do the same label swap for `NOT-DONE` tickets, keeping opencode's Notes.

## 5. Report

Append one row per ticket to `$REPORT`:

`| ID | PASS/GAVE-UP/NOT-DONE | fix rounds | merge commits (<repo>@<short sha>, …) | one-line note |`

Then add these sections:

- "Gates": new failures still present, and the number of baseline failures, per repo.
- "Left over": per repo, `git worktree list` entries and `git branch --list` branches the run created and did not remove, and the stash list. Do not delete them.
- "Morning review": per repo, `git -C <repo> log --oneline --first-parent RUN_BASE[<repo>]..HEAD`, and how to inspect the run: `opencode -s <SESSION>` or the `.jsonl` log.

Finish with a short summary and the report path.

Keep your own context small. Do not cat the run log. Rely on the script's compact output, the gate files and the reviewers' verdicts.
