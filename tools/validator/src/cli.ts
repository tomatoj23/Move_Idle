// CLI 入口：node src/cli.ts [--content <dir>] [--schema <dir>]（默认 cwd 下 content/ 与 schema/）。
// 契约（#26 AC）：结构化错误 JSON 到 stdout；退出码 0=合法 / 1=校验失败 / 2=环境错误。
// stdout 恒为单行 JSON 或空（exit 2 时诊断走 stderr），供批量生成 agent 直接解析。
import { validateContentLibrary } from "./index.ts";

interface CliArgs {
  content: string;
  schema: string;
}

function usageError(message: string): never {
  process.stderr.write(`validator: ${message}\nusage: node src/cli.ts [--content <dir>] [--schema <dir>]\n`);
  process.exit(2);
}

function parseArgs(argv: readonly string[]): CliArgs {
  const args: CliArgs = { content: "content", schema: "schema" };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg === "--content" || arg === "--schema") {
      const value = argv[i + 1];
      if (value === undefined) usageError(`missing value for ${arg}`);
      args[arg === "--content" ? "content" : "schema"] = value;
      i++;
    } else {
      usageError(`unknown argument: ${arg}`);
    }
  }
  return args;
}

try {
  const args = parseArgs(process.argv.slice(2));
  const report = validateContentLibrary({ contentDir: args.content, schemaDir: args.schema });
  process.stdout.write(JSON.stringify(report) + "\n");
  process.exit(report.ok ? 0 : 1);
} catch (err) {
  const message = err instanceof Error ? err.message : String(err);
  process.stderr.write(`validator error: ${message}\n`);
  process.exit(2);
}
