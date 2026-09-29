import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import type { ToolAnnotations } from "@modelcontextprotocol/sdk/types.js";
import { resultText, type ListedTool, type McpCallResult, McpServerError } from "./mcp";

/**
 * Local Cua Driver transport.
 *
 * Cua is intentionally reached through its stdio MCP proxy pointed at one of two
 * bounded local daemons. The daemon owns the reviewed capability manifest; OpenBot
 * still owns grants, action policy, and audit. This keeps Cua behind the same
 * governance path as every other tool instead of handing a raw MCP server directly
 * to an agent.
 */
export const listNeedsCredential = false;

const LIST_TIMEOUT_MS = 15_000;
const CALL_TIMEOUT_MS = 60_000;

type Connection = {
  url: string;
  token?: string;
  actorId?: string;
  botId?: string;
};

function socketFor(url: string): string {
  if (url === "builtin://cua-browser") {
    return (
      process.env.CUA_BROWSER_SOCKET?.trim() ||
      String.raw`\\.\pipe\senior-cua-browser`
    );
  }
  if (url === "builtin://cua-desktop") {
    return (
      process.env.CUA_DESKTOP_SOCKET?.trim() ||
      String.raw`\\.\pipe\senior-cua-desktop`
    );
  }
  throw new McpServerError("Cua Driver was asked to use an unknown local runtime.");
}

function executable(): string {
  return process.env.CUA_DRIVER_BIN?.trim() || "cua-driver";
}

async function withClient<T>(
  connection: Connection,
  use: (client: Client) => Promise<T>,
): Promise<T> {
  const transport = new StdioClientTransport({
    command: executable(),
    args: ["mcp", "--socket", socketFor(connection.url)],
  });
  const client = new Client({ name: "openbot-cua", version: "1.0.0" });

  try {
    await client.connect(transport);
    return await use(client);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new McpServerError(`Cua Driver local MCP failed: ${message.slice(0, 500)}`);
  } finally {
    await client.close().catch(() => {});
  }
}

/**
 * Only a destructive hint is promoted from an untrusted listing. Read-only hints
 * are deliberately ignored, matching the main MCP transport: a vendor may narrow
 * its own authority, never widen it.
 */
function declaredEffect(annotations: ToolAnnotations | undefined) {
  if (annotations?.destructiveHint !== true) return {};
  return { effect: "write", destructive: true } as const;
}

export async function listTools(connection: Connection): Promise<ListedTool[]> {
  return withClient(connection, async (client) => {
    const result = await client.listTools(undefined, { timeout: LIST_TIMEOUT_MS });
    return result.tools.map((tool) => ({
      name: tool.name,
      description: tool.description ?? "",
      inputSchema: (tool.inputSchema ?? {}) as Record<string, unknown>,
      ...declaredEffect(tool.annotations),
    }));
  });
}

export async function callTool(
  connection: Connection,
  toolName: string,
  args: Record<string, unknown>,
): Promise<McpCallResult> {
  return withClient(connection, async (client) => {
    const result = await client.callTool(
      { name: toolName, arguments: args },
      undefined,
      { timeout: CALL_TIMEOUT_MS },
    );
    const { text, truncated } = resultText(
      result.content,
      "structuredContent" in result ? result.structuredContent : undefined,
    );
    return { text, isError: result.isError === true, truncated };
  });
}
