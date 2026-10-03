# claude-plugins

Personal Claude Code plugins. Claude acts as the dispatcher: it hands tickets to another coding agent, reviews each result with Sonnet, sends fixes back and writes a report.

| Plugin | Implementing agent | Command |
| --- | --- | --- |
| `opencode-delegation` | [opencode](https://opencode.ai) | `/opencode-delegation:delegate` |
| `pi-delegation` | [pi](https://pi.dev) | `/pi-delegation:delegate` |

## Install

```
/plugin marketplace add chantharamanee-prat/claude-plugins
/plugin install pi-delegation@prt-workflow
/plugin install opencode-delegation@prt-workflow
```

## Usage

```
/pi-delegation:delegate [feature | ticket-path ...] [--max-rounds N]
```

The command picks up tickets in `.scratch/<feature>/issues/*.md` that have `status: open` and the `ready-for-agent` label, and works through them one at a time. It expects a clean working tree and is meant to run unattended.

## Requirements

- `pi` or `opencode` on `PATH`, already signed in to a model provider
- `node` and `bash` (Git Bash on Windows)
- Matt Pocock's skills in `~/.agents/skills` (`implement`, `tdd`, `code-review`)

Set `PI_MODEL` or `OPENCODE_MODEL` to override the agent's default model.

## Note

The dispatch prompts are tuned for my own setup (a machine without `rg`, English-only notes). Edit `commands/delegate.md` in each plugin to fit yours.
