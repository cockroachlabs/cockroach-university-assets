"""A stub "agent" so the labs need no LLM or API key.

A real assistant sends the conversation to a language model and gets back
text plus tool calls.
This stub returns the same shape of data, so what the app stores in
CockroachDB looks like what a real agent would produce.
"""

import re

MODEL = "talc-stub"

# Keyword -> (tool name, argument name) the stub pretends to call.
_TOOLS = [
    (r"\b(search|find|look up)\b", "search_docs", "query"),
    (r"\b(remember|note that)\b", "memory_create", "content"),
    (r"\b(remind|schedule)\b", "create_reminder", "text"),
    (r"\b(ticket|issue|bug)\b", "issue_search", "query"),
]


def reply(user_text: str, history_len: int = 0) -> dict:
    """Return an assistant message as a dict ready to store in messages.content."""
    tool_calls = [
        {"name": name, "args": {arg: user_text}}
        for pattern, name, arg in _TOOLS
        if re.search(pattern, user_text, re.IGNORECASE)
    ]
    if tool_calls:
        names = ", ".join(t["name"] for t in tool_calls)
        text = f"I would call {names} to help with that. (Talc uses a stub agent, so no real tools run.)"
    else:
        text = f"You said: {user_text!r}. This conversation now has {history_len + 2} messages."
    return {
        "text": text,
        "tool_calls": tool_calls,
        "metadata": {
            "model": MODEL,
            "tokens": {"input": len(user_text.split()) + 20 * history_len, "output": len(text.split())},
        },
    }
