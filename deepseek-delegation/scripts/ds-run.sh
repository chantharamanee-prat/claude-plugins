#!/usr/bin/env bash
# Runs one headless DeepSeek Harness (dsh) turn and prints a compact result:
#   exit=<code> session=<id>
#   <last assistant text, truncated>
# After the result a `state:` line reports worktrees=<n> dsh_procs=<n> [merges=<n>].
# The exit code only says how the CLI ended, not whether the work is done: judge by the state line and git.
# Set DS_RUN_BASE=<sha> to also count merge commits since the run began.
# usage: ds-run.sh <log.jsonl> [--session <id>] <message>
#        ds-run.sh --state        (print only the state line, e.g. to wait for running work)
set -uo pipefail
state() {
  # headless runs live inside "DeepSeek Harness.exe" next to the desktop app, so match the command line, not the name
  local procs
  if command -v powershell.exe >/dev/null; then
    procs=$(powershell.exe -NoProfile -Command "@(Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -match 'dsh-desktop-host.+cli\.js.+headless' }).Count" | tr -d '\r')
  else
    procs=$(ps -eo args 2>/dev/null | grep -cE '[d]sh(-desktop-host.+cli\.js)? .*headless')
  fi
  echo "state: worktrees=$(( $(git worktree list | wc -l) - 1 )) dsh_procs=$procs${DS_RUN_BASE:+ merges=$(git log --merges --oneline "$DS_RUN_BASE"..HEAD | wc -l | tr -d ' ')}"
}
if [ "$1" = --state ]; then state; exit; fi
log=$1; shift
mkdir -p "$(dirname "$log")"
resume=()
if [ "$1" = --session ]; then resume=(--session-id "$2"); shift 2; fi

dsh=$(command -v dsh || command -v dsh.cmd) || { echo "exit=127 session=null"; echo "dsh not on PATH (enable the dsh command in DeepSeek Harness)"; exit 127; }
here=$(cd "$(dirname "$0")" && pwd)
patches=(--patch "$here/headless.patch.yml")
[ -n "${DSH_PATCH:-}" ] && patches+=(--patch "$DSH_PATCH")  # e.g. pick the provider/model for headless runs
# The task goes in on stdin (`-`): on Windows dsh is a .cmd shim, and cmd.exe mangles long multi-line arguments.
printf '%s' "$*" | "$dsh" headless "${patches[@]}" --json "${resume[@]}" \
  --permission-mode "${DSH_PERMISSION_MODE:-danger-full-access}" --approval-policy never - >>"$log" 2>>"$log.err"
code=$?
node -e '
const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
let sid = null, text = null;
for (const l of lines) {
  let e; try { e = JSON.parse(l); } catch { continue; }
  if (e.type === "session") sid = e.sessionId; // log is appended per round; last session wins
  if (e.type === "final") text = e.text || (e.reason?.error ? `error: ${e.reason.error.code} ${e.reason.error.message}` : "");
}
console.log(`exit=${process.argv[2]} session=${sid}`);
console.log((text || "(no text output - see .err log)").slice(-4000));
' "$log" "$code"
state
