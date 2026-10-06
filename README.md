# claude-plugins

Personal Claude Code plugins. Claude acts as the dispatcher: it hands tickets to another coding agent, reviews each result with Sonnet, sends fixes back and writes a report.

| Plugin                | Implementing agent                               | Command                         |
| --------------------- | ------------------------------------------------ | ------------------------------- |
| `codex-delegation`    | [codex](https://developers.openai.com/codex/cli) | `/codex-delegation:delegate`    |
| `opencode-delegation` | [opencode](https://opencode.ai)                  | `/opencode-delegation:delegate` |
| `pi-delegation`       | [pi](https://pi.dev)                             | `/pi-delegation:delegate`       |

## Install

```
/plugin marketplace add chantharamanee-prat/claude-plugins
/plugin install pi-delegation@prt-workflow
/plugin install codex-delegation@prt-workflow
/plugin install opencode-delegation@prt-workflow
```

## Usage

```
/pi-delegation:delegate [feature | ticket-path ...] [--max-rounds N]
```

The command picks up tickets in `.scratch/<feature>/issues/*.md` that have `status: open` and the `ready-for-agent` label, and works through them one at a time. It expects a clean working tree and is meant to run unattended.

### Whole feature in parallel (opencode and codex)

```
/opencode-delegation:delegate-spec <feature> [--max-rounds N]
/codex-delegation:delegate-spec <feature> [--max-rounds N]
```

The agent runs the feature's tickets itself with Matt Pocock's `implement-spec` skill: parallel sub-agents in worktrees, one merge commit per ticket on the current branch. Claude runs the repo's typecheck and tests before and after, reviews each ticket's merge with Sonnet, and sends the fixes back. Faster than `delegate` when tickets do not block each other, but problems are found after the merge, not before it.

## Requirements

- `pi`, `opencode` or `codex` on `PATH`, already signed in to a model provider
- `node` and `bash` (Git Bash on Windows)
- Matt Pocock's skills in `~/.agents/skills` (`implement`, `implement-spec`, `tdd`, `code-review`)

Set `PI_MODEL`, `OPENCODE_MODEL` or `CODEX_MODEL` to override the agent's default model.

codex runs with `--dangerously-bypass-approvals-and-sandbox` (set in `codex-delegation/scripts/cx-run.sh`): like the other two agents it is not sandboxed, so only run it on repos and tickets you trust.

## Note

The dispatch prompts are tuned for my own setup (a machine without `rg`, English-only notes). Edit `commands/delegate.md` in each plugin to fit yours.
