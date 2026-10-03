#!/usr/bin/env bash
# Runs one headless pi turn and prints a compact result:
#   exit=<code> session=<id> stop=<reason>
#   <last assistant text, truncated>
# usage: pi-run.sh <log.jsonl> [--session <id>] [--name <t>] <message>
set -uo pipefail
log=$1; shift
mkdir -p "$(dirname "$log")"
# message_update events repeat the whole partial message on every delta; dropping them keeps the log small
pi -p --mode json --no-extensions --skill "$HOME/.agents/skills" ${PI_MODEL:+--model "$PI_MODEL"} "$@" </dev/null 2>>"$log.err" \
  | grep -v '^{"type":"message_update"' >>"$log"
code=${PIPESTATUS[0]}
node -e '
const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
let sid = null, text = null, stop = null;
for (const l of lines) {
  let e; try { e = JSON.parse(l); } catch { continue; }
  if (e.type === "session") sid = e.id; // log is appended per round; last session wins
  if (e.type === "message_end" && e.message?.role === "assistant") {
    stop = e.message.errorMessage ? `error: ${e.message.errorMessage}` : e.message.stopReason;
    const t = (e.message.content || []).filter(c => c.type === "text").map(c => c.text).join("\n");
    if (t) text = t;
  }
}
console.log(`exit=${process.argv[2]} session=${sid} stop=${stop}`);
console.log((text ?? "(no text output - see .err log)").slice(-4000));
' "$log" "$code"
