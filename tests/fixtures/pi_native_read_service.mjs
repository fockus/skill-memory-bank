// Only the external LLM transport is simulated; SDK, Tintin and read are real.
import { createServer } from "node:http";

export async function createReadService(path, marker) {
  const requests = [];
  let error, parentTurns = 0, leafTurns = 0;
  const server = createServer(async (req, res) => {
    try {
      if (req.method !== "POST" || req.url !== "/v1/responses" ||
          req.headers.authorization !== "Bearer mb-local-read-synthetic" || requests.length >= 4) {
        throw new Error("Unexpected local request/auth/budget");
      }
      let raw = "";
      for await (const chunk of req) {
        raw += chunk;
        if (raw.length > 262144) throw new Error("Request too large");
      }
      const body = JSON.parse(raw);
      const tools = (body.tools || []).map(tool => tool.name);
      const parent = tools.includes("mb_dispatch_subagent");
      if (!body.stream || body.model !== "gpt-4.1" ||
          !parent && JSON.stringify(tools) !== '["read"]') {
        throw new Error("Unexpected model or tool scope");
      }
      requests.push(body);
      let item, events;
      const turn = parent ? ++parentTurns : ++leafTurns;
      if (turn === 1) {
        item = { id: parent ? "fc_dispatch" : "fc_read", type: "function_call",
          call_id: parent ? "call_dispatch" : "call_read",
          name: parent ? "mb_dispatch_subagent" : "read",
          arguments: JSON.stringify(parent ? { role: "read-probe", task: `Read ${path} and report its content.` } : { path }),
          status: "completed" };
        events = [
          { type: "response.output_item.added", output_index: 0, item: { ...item, arguments: "", status: "in_progress" } },
          { type: "response.function_call_arguments.delta", output_index: 0, item_id: item.id, delta: item.arguments },
          { type: "response.function_call_arguments.done", output_index: 0, item_id: item.id, arguments: item.arguments },
          { type: "response.output_item.done", output_index: 0, item },
        ];
      } else {
        if (!body.input.some(item => item.type === "function_call_output" && JSON.stringify(item.output).includes(marker))) {
          throw new Error("Actual read result missing from follow-up request");
        }
        const text = parent ? "MB_PARENT_VERIFIED" : `READ_VERIFIED:${marker}`;
        item = { id: "msg_read", type: "message", role: "assistant", status: "completed",
          content: [{ type: "output_text", text, annotations: [] }] };
        events = [
          { type: "response.output_item.added", output_index: 0, item: { ...item, content: [], status: "in_progress" } },
          { type: "response.content_part.added", output_index: 0, content_index: 0, item_id: item.id, part: { type: "output_text", text: "", annotations: [] } },
          { type: "response.output_text.delta", output_index: 0, content_index: 0, item_id: item.id, delta: text },
          { type: "response.output_item.done", output_index: 0, item },
        ];
      }
      const response = { id: `resp_read_${requests.length}`, object: "response", created_at: 1,
        model: body.model, status: "completed", output: [item],
        usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2,
          input_tokens_details: { cached_tokens: 0 }, output_tokens_details: { reasoning_tokens: 0 } } };
      events.unshift({ type: "response.created", response: { ...response, status: "in_progress", output: [] } });
      events.push({ type: "response.completed", response });
      res.writeHead(200, { "content-type": "text/event-stream", connection: "close" });
      res.end(events.map((event, index) => `event: ${event.type}\ndata: ${JSON.stringify({ ...event, sequence_number: index })}\n\n`).join(""));
    } catch (failure) {
      error = failure.message;
      res.writeHead(400); res.end(error);
    }
  });
  await new Promise((done, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", done); });
  return { endpoint: `http://127.0.0.1:${server.address().port}/v1`, requests,
    get error() { return error; },
    async close() {
      const closed = new Promise(done => server.close(done));
      server.closeAllConnections(); await closed;
    } };
}
