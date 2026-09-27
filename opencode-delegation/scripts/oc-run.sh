#!/usr/bin/env bash
# Runs one headless opencode turn and prints a compact result:
#   exit=<code> session=<id>
#   <last assistant text, truncated>
# usage: oc-run.sh <log.jsonl> [--session <id>] [--title <t>] <message>
set -uo pipefail
log=$1; shift
mkdir -p "$(dirname "$log")"
opencode run --auto --format json ${OPENCODE_MODEL:+--model "$OPENCODE_MODEL"} "$@" >>"$log" 2>>"$log.err"
code=$?
py=$(command -v python3 || command -v python)
"$py" - "$log" "$code" <<'PY'
import json, sys
sid, texts = None, []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    sid = e.get("sessionID") or sid  # last session wins (log is appended per round)
    if e.get("type") == "text":
        texts.append(e.get("part", {}).get("text", ""))
print(f"exit={sys.argv[2]} session={sid}")
print((texts[-1] if texts else "(no text output - see .err log)")[-4000:])
PY
