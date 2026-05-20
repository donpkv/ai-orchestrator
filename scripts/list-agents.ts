import * as fs from "fs";
import * as path from "path";

const SUBTASKS_FILE = path.resolve(__dirname, "../subtasks.json");
const data = JSON.parse(fs.readFileSync(SUBTASKS_FILE, "utf-8"));

console.log("\n=== Subtask Registry ===\n");
console.log(
  ["ID", "Title", "Status", "Agent ID", "Last Run"]
    .map((h) => h.padEnd(24))
    .join("")
);
console.log("-".repeat(120));

for (const t of data.subtasks) {
  console.log(
    [t.id, t.title, t.status, t.agentId ?? "—", t.lastRunAt ? t.lastRunAt.slice(0, 19) : "—"]
      .map((v) => String(v).padEnd(24))
      .join("")
  );
}
console.log("");
