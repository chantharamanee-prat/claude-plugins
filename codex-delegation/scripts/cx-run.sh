#!/usr/bin/env bash
# Runs one headless codex turn and prints a compact result:
#   exit=<code> session=<id>
#   <last assistant text, truncated>
# usage: cx-run.sh <log.jsonl> [--session <id>] <message>
set -uo pipefail
log=$1; shift
mkdir -p "$(dirname "$log")"
resume=()
if [ "$1" = --session ]; then resume=(resume "$2"); shift 2; fi

codex exec "${resume[@]}" --json --dangerously-bypass-approvals-and-sandbox ${CODEX_MODEL:+--model "$CODEX_MODEL"} "$@" </dev/null >>"$log" 2>>"$log.err"  # stdin must be closed or codex waits on it
code=$?
node -e '
const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
let sid = null, text = null;
for (const l of lines) {
  let e; try { e = JSON.parse(l); } catch { continue; }
  if (e.type === "thread.started") sid = e.thread_id; // log is appended per round; last session wins
  if (e.type === "item.completed" && e.item?.type === "agent_message") text = e.item.text ?? "";
}
console.log(`exit=${process.argv[2]} session=${sid}`);
console.log((text ?? "(no text output - see .err log)").slice(-4000));
' "$log" "$code"
