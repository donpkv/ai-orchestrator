import * as fs from "fs";
import * as path from "path";
import * as dotenv from "dotenv";
import { Agent } from "@cursor/sdk";

dotenv.config({ path: path.resolve(__dirname, "../.env") });

const SUBTASKS_FILE = path.resolve(__dirname, "../subtasks.json");

interface Subtask {
  id: string;
  phase: string;
  title: string;
  status: "pending" | "running" | "done" | "failed";
  agentId: string | null;
  lastRunAt: string | null;
  prompt: string;
}

interface SubtasksFile {
  subtasks: Subtask[];
}

function loadSubtasks(): SubtasksFile {
  return JSON.parse(fs.readFileSync(SUBTASKS_FILE, "utf-8"));
}

function saveSubtasks(data: SubtasksFile): void {
  fs.writeFileSync(SUBTASKS_FILE, JSON.stringify(data, null, 2));
}

async function main() {
  const targetId = process.argv[2];

  if (!targetId) {
    console.error("Usage: npx ts-node scripts/run-subtask.ts <subtask-id>");
    console.error("Example: npx ts-node scripts/run-subtask.ts 1.1");
    process.exit(1);
  }

  if (!process.env.CURSOR_API_KEY) {
    console.error("ERROR: CURSOR_API_KEY not set. Copy .env.example to .env and fill in your key.");
    process.exit(1);
  }

  const data = loadSubtasks();
  const task = data.subtasks.find((t) => t.id === targetId);

  if (!task) {
    console.error(`Subtask ${targetId} not found in subtasks.json`);
    process.exit(1);
  }

  if (task.prompt === "PLACEHOLDER" || task.prompt.startsWith("PLACEHOLDER")) {
    console.error(`Subtask ${targetId} prompt is a PLACEHOLDER. Report back to the control chat to get the real prompt.`);
    process.exit(1);
  }

  console.log(`\n=== Running Subtask ${task.id}: ${task.title} ===\n`);

  task.status = "running";
  task.lastRunAt = new Date().toISOString();
  saveSubtasks(data);

  const agent = await Agent.create({
    apiKey: process.env.CURSOR_API_KEY!,
    model: { id: "composer-2" },
    local: { cwd: path.resolve(__dirname, "..") },
  });

  try {
    const run = await agent.send(task.prompt);

    for await (const event of run.stream()) {
      if (event.type === "assistant") {
        for (const block of event.message.content) {
          if (block.type === "text") process.stdout.write(block.text);
        }
      }
    }

    const result = await run.wait();

    const freshData = loadSubtasks();
    const freshTask = freshData.subtasks.find((t) => t.id === targetId)!;
    freshTask.agentId = (agent as any).agentId ?? null;
    freshTask.lastRunAt = new Date().toISOString();
    freshTask.status = result.status === "finished" ? "done" : "failed";
    saveSubtasks(freshData);

    if (result.status === "finished") {
      console.log(`\n\n=== Subtask ${targetId} DONE. Agent ID: ${(agent as any).agentId} ===`);
      console.log("Review the output above and the generated files, then report back to the control chat.");
    } else {
      console.error(`\n\n=== Subtask ${targetId} FAILED (status: ${result.status}) ===`);
      process.exit(2);
    }
  } catch (err: any) {
    const freshData = loadSubtasks();
    const freshTask = freshData.subtasks.find((t) => t.id === targetId)!;
    freshTask.status = "failed";
    saveSubtasks(freshData);
    console.error("Startup error:", err.message);
    process.exit(1);
  } finally {
    await (agent as any)[Symbol.asyncDispose]?.();
  }
}

main();
