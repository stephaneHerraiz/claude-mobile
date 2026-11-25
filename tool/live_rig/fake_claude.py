#!/usr/bin/env python3
"""Stand-in for `claude -p` in stream-json mode, for the live SSH test.

Speaks the wire format recorded in docs/superpowers/specs (spike result 2).
It is strict about what it reads: anything unexpected ends the process with
a message on stderr, so a client that drifts from the format fails loudly.
"""
import json
import os
import sys


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def die(message):
    sys.stderr.write("fake-claude: " + message + "\n")
    sys.exit(2)


def read():
    line = sys.stdin.readline()
    if not line:
        sys.exit(0)
    if not line.endswith("\n"):
        die("input line without trailing newline")
    try:
        return json.loads(line)
    except ValueError:
        die("input is not JSON: " + line[:80])


def main():
    args = sys.argv[1:]
    required = [
        "-p", "--input-format", "--output-format", "--verbose",
        "--include-partial-messages", "--permission-prompt-tool",
    ]
    for flag in required:
        if flag not in args:
            die("missing flag " + flag)
    if args[args.index("--permission-prompt-tool") + 1] != "stdio":
        die("permission prompt tool is not stdio")
    if "--resume" in args:
        session = args[args.index("--resume") + 1]
    elif "--session-id" in args:
        session = args[args.index("--session-id") + 1]
    else:
        die("neither --resume nor --session-id")

    if "--name" in args:
        # Like the real CLI (observed on 2.1.332): the name given at creation
        # is recorded in the session file as a custom title.
        name = args[args.index("--name") + 1]
        folder = os.path.expanduser("~/.claude/projects/-tmp-demo")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, session + ".jsonl"), "a") as f:
            f.write(json.dumps({"type": "custom-title", "customTitle": name,
                                "sessionId": session}) + "\n")

    # The model asked for, echoed in each permission request so that a test
    # can see which one the process was started with.
    model = args[args.index("--model") + 1] if "--model" in args else None
    note = "Create file" + (" (model %s)" % model if model else "")

    turn = 0
    while True:
        msg = read()
        if msg.get("type") != "user":
            die("expected a user message, got " + json.dumps(msg)[:80])
        text = msg["message"]["content"]
        if msg["message"].get("role") != "user" or not isinstance(text, str):
            die("malformed user message")
        turn += 1
        emit({"type": "system", "subtype": "init", "cwd": os.getcwd(),
              "session_id": session, "tools": ["Bash"],
              "model": "fake-model", "permissionMode": "default"})
        for piece in ("Wor", "king"):
            emit({"type": "stream_event", "session_id": session,
                  "event": {"type": "content_block_delta", "index": 0,
                            "delta": {"type": "text_delta", "text": piece}}})
        tool_id = "toolu_%d" % turn
        tool_input = {"command": "touch " + text, "description": note}
        emit({"type": "assistant", "session_id": session,
              "message": {"id": "msg_%da" % turn, "role": "assistant",
                          "content": [{"type": "text", "text": "Working"},
                                      {"type": "tool_use", "id": tool_id,
                                       "name": "Bash", "input": tool_input}]}})
        request_id = "req_%d" % turn
        emit({"type": "control_request", "request_id": request_id,
              "request": {"subtype": "can_use_tool", "tool_name": "Bash",
                          "display_name": "Bash", "input": tool_input,
                          "description": note,
                          "permission_suggestions": [],
                          "tool_use_id": tool_id}})
        reply = read()
        if reply.get("type") != "control_response":
            die("expected control_response, got " + json.dumps(reply)[:80])
        response = reply["response"]
        if response.get("subtype") != "success":
            die("control_response subtype is not success")
        if response.get("request_id") != request_id:
            die("control_response for the wrong request")
        decision = response["response"]
        if decision.get("behavior") == "allow":
            if decision.get("updatedInput") != tool_input:
                die("allow without the original input")
            content, is_error, final = "ok", False, "Done."
        elif decision.get("behavior") == "deny":
            content, is_error, final = decision.get("message", ""), True, "Denied."
        else:
            die("unknown behavior")
        emit({"type": "user", "session_id": session,
              "message": {"role": "user", "content": [
                  {"tool_use_id": tool_id, "type": "tool_result",
                   "content": content, "is_error": is_error}]}})
        emit({"type": "assistant", "session_id": session,
              "message": {"id": "msg_%db" % turn, "role": "assistant",
                          "content": [{"type": "text", "text": final}]}})
        emit({"type": "result", "subtype": "success", "is_error": False,
              "result": final, "total_cost_usd": 0.01 * turn,
              "session_id": session})


main()
