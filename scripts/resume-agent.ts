import * as path from "path";
import * as dotenv from "dotenv";
import { Agent } from "@cursor/sdk";
import * as readline from "readline";

dotenv.config({ path: path.resolve(__dirname, "../.env") });

async function main() {
  const agentId = process.argv[2];
  const followUp = process.argv.slice(3).join(" ");

  if (!agentId) {
    console.error("Usage: npx ts-node scripts/resume-agent.ts <agent-id> [follow-up message]");
    process.exit(1);
  }

  if (!process.env.CURSOR_API_KEY) {
    console.error("ERROR: CURSOR_API_KEY not set.");
    process.exit(1);
  }

  const message = followUp || await askQuestion("Follow-up message: ");

  console.log(`\nResuming agent ${agentId}...\n`);

  const agent = Agent.resume(agentId, {
    apiKey: process.env.CURSOR_API_KEY!,
    model: { id: "composer-2" },
    local: { cwd: path.resolve(__dirname, "..") },
  });

  try {
    const run = await agent.send(message);
    for await (const event of run.stream()) {
      if (event.type === "assistant") {
        for (const block of event.message.content) {
          if (block.type === "text") process.stdout.write(block.text);
        }
      }
    }
    await run.wait();
    console.log("\n\n=== Resume complete ===");
  } finally {
    await agent[Symbol.asyncDispose]();
  }
}

function askQuestion(q: string): Promise<string> {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(q, (ans) => { rl.close(); resolve(ans); }));
}

main();
