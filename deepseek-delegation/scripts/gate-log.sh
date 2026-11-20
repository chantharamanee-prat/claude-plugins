#!/usr/bin/env bash
# Prints the shell commands dsh actually ran (from the run log) that match a pattern,
# each with its exit code and the tail of its output. Evidence for gate checks.
# usage: gate-log.sh <log.jsonl> [regex]   (default regex: test/typecheck/build/lint runner commands)
set -uo pipefail
node -e '
const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
const re = process.argv[2] ? new RegExp(process.argv[2], "i") : /(npm|pnpm|yarn|bun|npx|dotnet|flutter|dart|cargo|go|make)\s+(run\s+)?\S*(test|typecheck|build|lint|analyze|check|vet)|\b(pytest|vitest|jest|tsc)\b/i;
const calls = new Map(); // callId -> command
let n = 0;
for (const l of lines) {
  let e; try { e = JSON.parse(l); } catch { continue; }
  if (e.type === "tool_call" && typeof e.input?.command === "string") calls.set(e.callId, e.input.command);
  if (e.type !== "tool_result" || !calls.has(e.callId)) continue;
  const cmd = calls.get(e.callId);
  if (!re.test(cmd)) continue;
  const out = typeof e.result === "string" ? e.result : JSON.stringify(e.result ?? "");
  // dsh appends "[exit code: N]" for non-zero exits (on Windows pwsh reports any failure as 1)
  const exit = out.match(/\[exit code: (-?\d+)\]\s*$/)?.[1] ?? (e.status === "completed" ? 0 : e.status);
  console.log(`#${++n} $ ${cmd.slice(0, 300)}\nexit=${exit}\n${out.slice(-500)}\n`);
}
if (!n) console.log("(no matching commands in the log)");
' "$1" "${2:-}"
