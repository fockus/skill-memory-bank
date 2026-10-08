// Composed, adapter-owned leaf profiles; never overwrite a foreign named agent.
import { readFile, writeFile, mkdir, readdir } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";

export const nativeDelegationTools = new Set(["subagent", "Agent", "SubagentWorkflow", "get_subagent_result", "steer_subagent", "stop_subagent"]);
const builtins = new Set(["bash", "read", "write", "edit", "grep", "find", "ls"]);

export function roleModel(ctx, role, runId, authorization) {
  if (!role?.agent) throw new Error("Missing configured agent");
  if (!ctx.model?.provider || !ctx.model?.id) throw new Error("Missing parent model/provider");
  const aliases = new Set(["opus", "sonnet", "haiku", "inherit"]);
  const model = !role.model || aliases.has(role.model) ? `${ctx.model.provider}/${ctx.model.id}` : role.model;
  if (!ctx.modelRegistry.getAvailable().some(row => `${row.provider}/${row.id}` === model)) throw new Error(`Unavailable model: ${model}`);
  if (model.split("/")[0] !== ctx.model.provider && !(authorization?.runId === runId && authorization.provider === model.split("/")[0])) throw new Error("Cross-provider model requires run-specific owner authorization");
  return model;
}

export async function discoverTintinRole(agent, cwd, agentDir, decoder) {
  const candidates = new Map();
  for (const folder of [join(agentDir, "agents"), join(cwd, ".agents", "agents"), join(cwd, ".pi", "agents")]) {
    let files;
    try { files = await readdir(folder); } catch (error) { if (error.code === "ENOENT") continue; throw error; }
    for (const file of files.filter(name => name.endsWith(".md")).sort()) {
      const source = join(folder, file);
      const parsed = await decoder("agent", source, cwd);
      const name = parsed.frontmatter.name || file.slice(0, -3);
      if (candidates.has(name) && candidates.get(name).folder === folder) throw new Error(`Ambiguous configured agent: ${name}`);
      candidates.set(name, { source, folder, ...parsed });
    }
  }
  const result = candidates.get(agent);
  if (!result || result.frontmatter.enabled === false || result.frontmatter.disabled === true) throw new Error(`Missing or disabled configured agent: ${agent}`);
  return result;
}

export async function composeLeaf({ backend, role, model, runId, cwd, source, parsed, tools }) {
  const fm = parsed.frontmatter;
  if (fm.disabled === true || fm.enabled === false) throw new Error(`Disabled configured agent: ${role.agent}`);
  if (backend === "tintin" && (role.isolation || fm.isolation && fm.isolation !== "off" || fm.memory || fm.runner)) {
    throw new Error("Tintin unsupported isolation, auto-commit, memory or external runner; refusing before profile mutation");
  }
  const declared = tools || (Array.isArray(fm.tools) ? fm.tools : String(fm.tools || "").split(",").map(name => name.trim()).filter(Boolean));
  if (!declared.length) throw new Error(`Missing explicit required tool scope for ${role.agent}`);
  const scoped = declared.filter(name => !nativeDelegationTools.has(name));
  if (backend === "tintin" && scoped.some(name => !builtins.has(name))) throw new Error(`Tintin cannot preserve required tools for ${role.agent}`);
  const name = `mb-leaf-${createHash("sha256").update(`${runId}:${backend}:${role.agent}`).digest("hex").slice(0, 20)}`;
  const header = { ...fm, name, model: backend === "nico" && !role.model || ["opus", "sonnet", "haiku", "inherit"].includes(role.model) ? "inherit" : model,
    tools: scoped.join(", "), extensions: [], subagentOnlyExtensions: [],
    allowNestedSubagents: false, allowedAgents: [], allowed_subagents: "none", exclude_extensions: "pi-subagents, @tintinweb/pi-subagents", mb_origin_agent: role.agent };
  if (backend === "tintin") { header.model = model; header.skills = false; header.persist_session = false; header.isolation = "off"; }
  // JSON values are valid YAML and avoid quoting/CSV injection in frontmatter.
  const body = `---\n${Object.entries(header).map(([key, value]) => `${key}: ${JSON.stringify(value)}`).join("\n")}\n---\n\n${parsed.body}\n`;
  const folder = join(cwd, ".pi", "agents");
  const file = join(folder, `${name}.md`);
  await mkdir(folder, { recursive: true });
  try { await writeFile(file, body, { flag: "wx", mode: 0o600 }); }
  catch (error) {
    if (error.code !== "EEXIST") throw error;
    if (await readFile(file, "utf8") !== body) throw new Error("Retained role/model/tool contract drift; owner reconciliation required");
  }
  return { agent: role.agent, runtimeAgent: name, model, tools: scoped, source,
    sourceHash: createHash("sha256").update(await readFile(source)).digest("hex"),
    profile: file, profileHash: createHash("sha256").update(body).digest("hex") };
}
