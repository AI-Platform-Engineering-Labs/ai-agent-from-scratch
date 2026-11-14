# ai-agent-from-scratch

A tiny tool-calling AI agent in a single Python file, with no frameworks. The goal is to see every layer of how an agent works and how to call a model.

## How it works

```
while not done:
    response = model(messages, tools)
    if the model asked for tools -> run them, append results, loop
    else -> it's finished
```

- **Stateless model:** "memory" is just the `messages` list, resent on every call.
- **Tools:** plain Python functions plus a JSON schema. The model only *requests* a call; your code runs it.
- **Guardrails:** `MAX_STEPS` caps the loop, tool errors are returned to the model, and `run_shell` needs your approval for each command.

## Run it

```bash
pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...
python agent.py "How many .py files are in this folder, and which is the biggest?"
```

Each step prints the stop reason, token counts, the tool call and its result. Watch the input tokens grow: that is the whole history being resent.

## Experiments

1. Give it a task needing several tools in a row, such as "find the largest file here and summarize it".
2. Deny a shell command and watch how it recovers.
3. Set `MAX_STEPS = 2` and give it a harder task to see the cutoff.
4. Add your own tool (`fetch_url`, `write_file`): a function, a schema, and a line in `TOOL_FUNCS`.

## Next

Move the tools behind an MCP server so the same loop can use any MCP server's tools.

## Deploy to production

An HTTP version of the agent (`service/`), Terraform for Azure (`infra/terraform/`) and Kubernetes manifests (`k8s/`) are in this repo. See [docs/deploy-aks.md](docs/deploy-aks.md).
