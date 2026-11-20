#!/usr/bin/env bash
# Runs one headless DeepSeek Harness (dsh) turn and prints a compact result:
#   exit=<code> session=<id>
#   <last assistant text, truncated>
# usage: ds-run.sh <log.jsonl> [--session <id>] <message>
set -uo pipefail
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
