#!/usr/bin/env bash
# Runs one headless opencode turn and prints a compact result:
#   exit=<code> session=<id>
#   <last assistant text, truncated>
# usage: oc-run.sh <log.jsonl> [--session <id>] [--title <t>] <message>
set -uo pipefail
log=$1; shift
mkdir -p "$(dirname "$log")"
opencode run --auto --format json ${OPENCODE_MODEL:+--model "$OPENCODE_MODEL"} "$@" </dev/null >>"$log" 2>>"$log.err"  # stdin must be closed or opencode waits on it
code=$?
node -e '
const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
let sid = null, text = null;
for (const l of lines) {
  let e; try { e = JSON.parse(l); } catch { continue; }
  sid = e.sessionID || sid; // log is appended per round; last session wins
  if (e.type === "text") text = e.part?.text ?? "";
}
console.log(`exit=${process.argv[2]} session=${sid}`);
console.log((text ?? "(no text output - see .err log)").slice(-4000));
' "$log" "$code"
