---
description: Rules for all Claude/Anthropic API integration code
globs: ["backend/app/ai/**", "backend/app/api_chat.py", "backend/app/main.py"]
alwaysApply: false
---

# Anthropic integration rules

The AI layer explains, chats, and audits. It NEVER computes routes (the deterministic engine
does) and NEVER invents safety guidance (the corpus does). Every design must survive the judge
question "isn't this an AI wrapper?" — the answer is this separation.

- System prompts embed the full structured corpus (it's small) with prompt caching on the
  corpus block; log cache hits. No vector DB unless the corpus outgrows this.
- Structured output is schema-enforced (tool-use / structured output), temperature low.
- Every safety claim in a response must carry a citation referencing a corpus doc id;
  validate citations server-side against `backend/corpus/sources.json` and reject/retry
  uncited claims.
- The S3.2 agent loop is hand-rolled with the Anthropic SDK (`while stop_reason == "tool_use"`),
  capped (~15 iterations) with graceful partial results; findings must link to actual tool-call
  evidence, validated server-side.
- Safety behaviors: emergencies → "call 911 first"; uncorpused topics → honest deferral, never
  invented advice.
- `ANTHROPIC_API_KEY` from env only. Prompt files are committed (they're part of the original
  work story).
