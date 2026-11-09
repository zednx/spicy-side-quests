// Line-based prompts that also work when answers are piped in (readline's question()
// drops lines that arrive before it asks). End of input means "use the default".
import readline from "node:readline";

export interface Prompter {
  /** Asks a question; returns the trimmed answer, or `def` on an empty answer or end of input. */
  ask(question: string, def?: string): Promise<string>;
  close(): void;
}

export function createPrompter(): Prompter {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: !!process.stdin.isTTY });
  const queue: string[] = [];
  const waiting: ((line: string | null) => void)[] = [];
  let closed = false;
  rl.on("line", (line) => {
    const w = waiting.shift();
    if (w) w(line);
    else queue.push(line);
  });
  rl.on("close", () => {
    closed = true;
    while (waiting.length) waiting.shift()!(null);
  });
  const next = (): Promise<string | null> => {
    if (queue.length) return Promise.resolve(queue.shift()!);
    if (closed) return Promise.resolve(null);
    return new Promise((resolve) => waiting.push(resolve));
  };
  return {
    async ask(question, def) {
      rl.setPrompt(def ? `${question}\n  [${def}]: ` : `${question}\n  : `);
      rl.prompt();
      const line = await next();
      if (!process.stdin.isTTY) process.stdout.write((line ?? "") + "\n"); // keep piped transcripts readable
      if (line === null && def === undefined) throw new Error("Setup cancelled: no more input.");
      return line?.trim() || def || "";
    },
    close: () => rl.close(),
  };
}
