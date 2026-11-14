#!/usr/bin/env python3
"""
A tiny agent: ~100 lines, no frameworks.

The whole idea:
    while not done:
        response = model(messages, tools)
        if the model asked for tools -> run them, append results, loop
        else -> it's finished, print the answer

Setup:
    pip install anthropic
    export ANTHROPIC_API_KEY=sk-ant-...
Run:
    python agent.py "How many .py files are in this folder and what is the biggest one?"
"""
import os
import subprocess
import sys

import anthropic

MODEL = "claude-sonnet-5-5"
MAX_STEPS = 10  # hard stop so a confused agent can't loop forever

client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from the environment

# --------------------------------------------------------------------------
# 1. TOOLS: plain Python functions + a JSON schema that describes each one.
#    The model never runs anything. It only asks; our code decides.
# --------------------------------------------------------------------------

def list_dir(path: str = ".") -> str:
    return "\n".join(sorted(os.listdir(path)))


def read_file(path: str) -> str:
    with open(path, "r", errors="replace") as f:
        return f.read()[:5000]  # cap output so we don't flood the context


def run_shell(command: str) -> str:
    # Human-in-the-loop: the agent proposes, you approve.
    if input(f"    Run `{command}`? [y/N] ").strip().lower() != "y":
        return "User denied this command."
    p = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
    return (p.stdout + p.stderr)[:5000] or "(no output)"


TOOL_FUNCS = {"list_dir": list_dir, "read_file": read_file, "run_shell": run_shell}

TOOLS = [
    {
        "name": "list_dir",
        "description": "List files and folders in a directory.",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string", "description": "Directory path, default '.'"}},
        },
    },
    {
        "name": "read_file",
        "description": "Read the first 5000 characters of a text file.",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"],
        },
    },
    {
        "name": "run_shell",
        "description": "Run a shell command and return its output. The user must approve each command.",
        "input_schema": {
            "type": "object",
            "properties": {"command": {"type": "string"}},
            "required": ["command"],
        },
    },
]

# --------------------------------------------------------------------------
# 2. THE LOOP
# --------------------------------------------------------------------------

def run_agent(goal: str) -> None:
    # The model is stateless. "Memory" is just this list, resent on every call.
    messages = [{"role": "user", "content": goal}]

    for step in range(1, MAX_STEPS + 1):
        response = client.messages.create(
            model=MODEL,
            max_tokens=1024,
            system="You are a careful assistant that completes tasks using tools. "
                   "Use tools to gather facts instead of guessing. Be concise.",
            tools=TOOLS,
            messages=messages,
        )
        u = response.usage
        print(f"\n--- step {step} | stop_reason={response.stop_reason} "
              f"| tokens in={u.input_tokens} out={u.output_tokens}")

        # Keep the assistant turn in history exactly as returned.
        messages.append({"role": "assistant", "content": response.content})

        # Not asking for a tool? Then the model is done.
        if response.stop_reason != "tool_use":
            for block in response.content:
                if block.type == "text":
                    print(f"\nFINAL ANSWER:\n{block.text}")
            return

        # Otherwise run every requested tool and send the results back.
        results = []
        for block in response.content:
            if block.type == "text" and block.text.strip():
                print(f"  thinking: {block.text.strip()}")
            elif block.type == "tool_use":
                print(f"  tool call: {block.name}({block.input})")
                try:
                    output = TOOL_FUNCS[block.name](**block.input)
                except Exception as e:  # errors go back to the model so it can adapt
                    output = f"ERROR: {e}"
                print(f"  result: {output[:200]!r}{'...' if len(output) > 200 else ''}")
                results.append({"type": "tool_result", "tool_use_id": block.id, "content": output})

        messages.append({"role": "user", "content": results})

    print(f"\nStopped: hit MAX_STEPS={MAX_STEPS} without a final answer.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit('Usage: python agent.py "your goal here"')
    run_agent(" ".join(sys.argv[1:]))
