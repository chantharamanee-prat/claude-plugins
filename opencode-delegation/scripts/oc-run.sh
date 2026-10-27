#!/usr/bin/env bash
# Runs one headless opencode turn and prints a compact result:
#   exit=<code> session=<id>
#   <last assistant text, truncated>
#   state: opencode_procs=<n> <repo>: worktrees=<n> [merges=<n>] ...
# The exit code only says how the CLI ended, not whether the work is done: judge by the state line and git.
# Set OC_REPOS="<dir>=<sha> ..." to report each repo and count its merge commits since <sha>.
# Without it, OC_RUN_BASE=<sha> does the same for the current repo only.
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
procs=$( (ps aux 2>/dev/null || ps -ef 2>/dev/null) | grep -c 'bin/[o]pencode')
state="state: opencode_procs=$procs"
for r in ${OC_REPOS:-.=${OC_RUN_BASE:-}}; do
  [[ $r == *=* ]] || r+==
  dir=${r%%=*}; base=${r#*=}
  state+=" $dir: worktrees=$(( $(git -C "$dir" worktree list | wc -l) - 1 ))${base:+ merges=$(git -C "$dir" log --merges --oneline "$base"..HEAD | wc -l | tr -d ' ')}"
done
echo "$state"
