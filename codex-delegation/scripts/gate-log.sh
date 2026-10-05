#!/usr/bin/env bash
# Prints the shell commands codex actually ran (from the run log) that match a pattern,
# each with its exit code and the tail of its output. Evidence for gate checks.
# usage: gate-log.sh <log.jsonl> [regex]   (default regex: test/typecheck/build/lint runner commands)
set -uo pipefail
node -e '
const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
const re = process.argv[2] ? new RegExp(process.argv[2], "i") : /(npm|pnpm|yarn|bun|npx|dotnet|flutter|dart|cargo|go|make)\s+(run\s+)?\S*(test|typecheck|build|lint|analyze|check|vet)|\b(pytest|vitest|jest|tsc)\b/i;
let n = 0;
for (const l of lines) {
  let e; try { e = JSON.parse(l); } catch { continue; }
  const i = e.item;
  if (e.type !== "item.completed" || i?.type !== "command_execution") continue;
  const cmd = i.command ?? "";
  if (!re.test(cmd)) continue;
  console.log(`#${++n} $ ${cmd.slice(0, 300)}\nexit=${i.exit_code ?? "?"}\n${String(i.aggregated_output ?? "").slice(-500)}\n`);
}
if (!n) console.log("(no matching commands in the log)");
' "$1" "${2:-}"
