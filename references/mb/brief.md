# /mb brief — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `brief <topic>` — Formalize a raw request plus attached documents into a one-page brief under `briefs/<topic>/` — first stage of `brief → discuss → sdd → work`. `[--request <text> \| --request-file <path>] [--input <path>]… [--auto]`; `--input` is repeatable. Not an interview: at most five clarifying questions. See `### brief` below / `commands/brief.md`.

### brief <topic>

`/mb brief <topic> [--request <text> | --request-file <path>] [--input <path>]… [--auto]`

Turn a raw request plus its attached documents into a validated one-page brief stored with its sources under `briefs/<topic>/`, so the work enters the pipeline already shaped: `brief → discuss → sdd → work`. Deliberately **not** an interview — `/mb discuss` owns the deep elicitation; briefing asks at most five clarifying questions, and only when the essence or the goal cannot be extracted from the request and its inputs.

**Alias** for `/brief` — dispatch to `commands/brief.md` for the canonical workflow.

- `--request <text>` — the request inline. `--request-file <path>` — the request read from a file. At most one of the two: passing both is `error=usage`, exit 2; passing neither leaves the text of the user message that carried the invocation as the request.
- `--input <path>` — **repeatable**: each occurrence names one source document to scan and copy into `inputs/`.
- `--auto` — skip the clarifying-question gate and infer on best effort; requires a non-empty `assumptions_note`.

There is no overwrite or re-publish flag: re-formalizing happens on a new `<topic>`, or after the user deletes `briefs/<topic>/` by hand.

**Underlying:** `"$SKILL_DIR/scripts/mb-brief.sh" create --mb <bank> --topic <topic> --candidate <path> [--input <path>]… [--auto]` — the only path that publishes a brief.
