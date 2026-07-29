#!/usr/bin/env bun

import { $ } from "bun";

const LM_STUDIO_URL =
  process.env.LM_STUDIO_URL ??
  "http://localhost:1234/v1/chat/completions";

const MODEL = process.env.LM_STUDIO_MODEL ?? "qwen2.5-coder-7b-instruct";

const SYSTEM_PROMPT = `
You are a git commit message generator.

Rules:
- Output ONLY the commit message
- No explanations
- No markdown
- No quotes
- Keep it concise and specific

Format:
area: short specific description

Optional body:
If the change contains multiple meaningful updates, add a blank line and then 2-5 bullet points using "- ".

Examples:
auth: add password visibility toggle

api: validate refresh token before creating session

tooling: improve commit generation workflow

deps: bump react and next versions

ui: support loading and disabled button states
`;

async function generateCommitMessage(diff: string, files: string[]) {
  const response = await fetch(LM_STUDIO_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: `Changed files:
${files.join("\n")}

Staged diff:
${diff.slice(0, 8000)}`
        },
      ],
      temperature: 0.1,
      max_tokens: 200,
    }),
  });

  if (!response.ok) {
    throw new Error(await response.text());
  }

  const data = await response.json();

  return (data.choices?.[0]?.message?.content ?? "").trim();
}

async function main() {
  const filesText = await $`git diff --cached --name-only`.text();

  const files = filesText
    .split("\n")
    .map((f) => f.trim())
    .filter(Boolean);

  if (files.length === 0) {
    console.error("❌ Nothing staged");
    process.exit(1);
  }

  const diff = await $`git diff --cached`.text();

  console.log("🤖 Generating commit message...\n");

  const message = await generateCommitMessage(diff, files);

  console.log(message);
  console.log();

  const answer = prompt("Commit with this message? (y/n): ")
    ?.trim()
    .toLowerCase();

  if (answer !== "y") {
    console.log("Cancelled.");
    return;
  }

  const lines = message.split("\n");
  const subject = lines[0] ?? "";
  const body = lines.slice(1).join("\n").trim();

  if (body) {
    await $`git commit -m ${subject} -m ${body}`;
  } else {
    await $`git commit -m ${subject}`;
  }

  console.log("✅ Committed successfully!");
}

main().catch((err) => {
  console.error("❌", err instanceof Error ? err.message : String(err));
  process.exit(1);
});