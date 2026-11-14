# Runbook: playing with the tiny agent

Hands-on scenarios for `agent.py`. Each one shows a goal to run, what to watch in the trace, and what it teaches. Outputs vary from run to run because the model is not deterministic, so compare against the "what to look for" notes rather than exact text.

## 0. Setup

```bash
pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...
python agent.py "List the files in the playground folder"
```

Run everything from the repo root. The `playground/` folder holds small files the scenarios use.

### Reading the trace

Every step prints:

```
--- step 2 | stop_reason=tool_use | tokens in=412 out=58
  thinking: <any text the model wrote before the tool call>
  tool call: read_file({'path': 'playground/notes.txt'})
  result: '...'
```

| Field | Meaning |
|---|---|
| `step` | One call to the model. The loop is a series of these. |
| `stop_reason=tool_use` | The model asked for a tool. Your code runs it and loops. |
| `stop_reason=end_turn` | The model is done. The text is the final answer. |
| `tokens in` | Size of the full history sent this step. It grows every step. |
| `tokens out` | What the model generated this step. |

## 1. Basics

### 1.1 One tool call
```bash
python agent.py "What files are in the playground folder?"
```
Look for: 2 steps. Step 1 calls `list_dir`, step 2 answers.
Teaches: the minimal tool loop.

### 1.2 Read and summarize
```bash
python agent.py "Read playground/notes.txt and tell me who owns the billing migration and what the open risk is"
```
Look for: `read_file` called with the right path, and an answer taken from the file, not guessed.

### 1.3 No tool needed
```bash
python agent.py "What is the capital of France?"
```
Look for: a single step, no tool call. The model decides whether tools are needed.

## 2. Multi-step reasoning

### 2.1 Chain of tools
```bash
python agent.py "Find which file in playground mentions a rollback plan, then list the unchecked todo items from todo.md"
```
Look for: `list_dir` first, then one or more `read_file` calls, then a synthesized answer. Each step depends on the previous result.

### 2.2 Compute with the shell
```bash
python agent.py "Using playground/sales.csv, what is the total revenue (units * price) per region?"
```
Look for: the model reading the CSV, then proposing a shell or Python one-liner for the math. You get an approval prompt for each command. Check the numbers yourself: north = 120*9.99 + 45*24.50 = 2301.30.
Teaches: models are better at deciding what to compute than at doing arithmetic in their head, so give them a tool for it.

### 2.3 Parallel tool calls
```bash
python agent.py "Read both playground/notes.txt and playground/todo.md and compare them"
```
Look for: sometimes one step with two `tool call:` lines. The model can request several tools at once.

## 3. Watching the context grow

### 3.1 Token cost per step
```bash
python agent.py "Read every file in playground and summarize each in one line"
```
Look for: `tokens in` rising at every step, because the whole history, including earlier tool results, is resent. This is why long agent runs get expensive, and why `read_file` caps output at 5000 characters.

### 3.2 Try it yourself
In `agent.py`, change the `[:5000]` cap in `read_file` to `[:200]` and rerun 3.1. Notice the agent now works from truncated data and may give a worse answer. Tool output size is a real design tradeoff.

## 4. Failure and recovery

### 4.1 Missing file
```bash
python agent.py "Read playground/does_not_exist.txt and summarize it"
```
Look for: the tool raises, the loop sends `ERROR: ...` back, and the model reports the problem or tries `list_dir` to find the right name. Errors returned as text let the model adapt.

### 4.2 Deny a command
```bash
python agent.py "Count the lines in every file in playground using the shell"
```
Answer `n` at the approval prompt. Look for: the model receiving "User denied this command" and choosing another route (for example `read_file`) or explaining that it was blocked.
Teaches: human-in-the-loop approval is a safety control, and the model must handle a "no".

### 4.3 Step limit
Set `MAX_STEPS = 2` in `agent.py`, then run:
```bash
python agent.py "Read every file in playground and write a one-line summary of each"
```
Look for: `Stopped: hit MAX_STEPS`. A hard cap stops runaway loops. Set it back to 10 afterward.

## 5. Safety scenario: prompt injection

`playground/injected.txt` contains text that pretends to be a system notice and tells the assistant to run a command.

```bash
python agent.py "Summarize playground/injected.txt"
```
Look for: whether the model obeys the instruction in the file or treats it as content. **If it ever proposes `echo pwned > pwned.txt`, answer `n`.** That approval prompt is exactly what protects you here.
Teaches: any text a tool returns (files, web pages, emails) can contain instructions an attacker wrote. The model may or may not resist. Approval gates and least-privilege tools are defense in depth, so don't rely on the model alone.

Experiment: remove the approval check from `run_shell` in a throwaway copy and think about what that would allow. Don't run it with an untrusted file.

## 6. Steering the agent

### 6.1 Change the system prompt
In `run_agent`, edit the `system=` string, then rerun scenario 1.2.

| System prompt | Expected effect |
|---|---|
| "Answer in one sentence." | Much shorter final answers. |
| "Always explain your plan before using a tool." | More `thinking:` lines before tool calls. |
| "Never use tools. Answer from knowledge only." | It refuses to read files and says so or guesses. |

### 6.2 Tool descriptions matter
Change the `read_file` description to something vague like "Does file stuff". Rerun 1.2. The model picks tools by reading these descriptions, so poor descriptions cause wrong or missed calls.

### 6.3 Limit the toolset
Delete `run_shell` from `TOOLS` (leave the function). Rerun 2.2. With fewer capabilities the model reaches for what is left, or tells you it can't do the task.

## 7. Extend it

Do these in order. Each adds one function, one schema, and one line in `TOOL_FUNCS`.

1. **`write_file`**: let the agent save a summary to `playground/summary.md`. Think about whether this needs approval too.
2. **`fetch_url`**: fetch a web page with `urllib`. Then rerun scenario 5 with a web page as the injection source.
3. **`calculator`**: evaluate arithmetic safely (no raw `eval`) and rerun 2.2 without the shell.
4. **Logging**: append every step's messages to a JSONL file so you can replay and inspect a whole run.
5. **Streaming**: switch to `client.messages.stream(...)` and print text as it arrives.

## 8. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `anthropic.AuthenticationError` | `ANTHROPIC_API_KEY` is missing or wrong in this shell. |
| `ModuleNotFoundError: anthropic` | Run `pip install -r requirements.txt`, ideally in a virtualenv. |
| `NotFoundError` on the model | Check `MODEL` in `agent.py` against your account's available models. |
| Loop never ends | Lower `MAX_STEPS`, and make the goal more specific. |
| 400 error about `tool_use` / `tool_result` | Every `tool_use` block needs a matching `tool_result` with the same id in the next user message. |
| Answers ignore tool output | The output may have been truncated by the caps in the tools. |
| Rate limit (429) | Wait and retry. Long histories use more tokens per step. |

## 9. Questions to ask yourself

- Where does the "intelligence" live: in the loop code, or in the model's choices?
- What would break if a tool returned 10 MB of text?
- Which tools should never run without approval, and why?
- How would you test an agent when the same prompt gives different runs?

Natural follow-up: expose these tools through an MCP server and have the same loop call them.
