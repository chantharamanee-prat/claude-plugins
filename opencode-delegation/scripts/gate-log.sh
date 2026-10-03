#!/usr/bin/env bash
# Prints the shell commands opencode actually ran (from the run log) that match a pattern,
# each with its exit code and the tail of its output. Evidence for gate checks.
# usage: gate-log.sh <log.jsonl> [regex]   (default regex: test/typecheck/build/lint runner commands)
set -uo pipefail
node -e '
const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
const re = process.argv[2] ? new RegExp(process.argv[2], "i") : /(npm|pnpm|yarn|bun|npx|dotnet|flutter|dart|cargo|go|make)\s+(run\s+)?\S*(test|typecheck|build|lint|analyze|check|vet)|\b(pytest|vitest|jest|tsc)\b/i;
let n = 0;
for (const l of lines) {
  let e; try { e = JSON.parse(l); } catch { continue; }
  const p = e.part;
  if (e.type !== "tool_use" || !["shell", "bash"].includes(p?.tool)) continue;
  const cmd = p.state?.input?.command ?? "";
  if (!re.test(cmd)) continue;
  const exit = p.state?.metadata?.metadata?.exit ?? p.state?.metadata?.exit ?? "?";
  console.log(`#${++n} $ ${cmd.slice(0, 300)}\ncwd=${p.state?.input?.workdir ?? "."} exit=${exit}\n${String(p.state?.output ?? "").slice(-500)}\n`);
}
if (!n) console.log("(no matching commands in the log)");
' "$1" "${2:-}"
