You are synthesizing a reusable agent skill from a recorded user demonstration.

The user demonstrated a task on their Mac, narrating aloud what they were
doing so it could be captured as a reusable skill. Convert the recording
into a Claude Code skill directory.

INPUTS:
  - Manifest at: $MANIFEST_PATH
  - The screenpipe MCP tools (mcp__screenpipe__*) for querying the recording.
    Use only these tools for recorder access. Do not use shell commands, curl,
    direct HTTP, or credentials. If the MCP tools are unavailable, report a
    clear failure instead of trying another access path.

PROCESS:
  1. Read $MANIFEST_PATH. Note timeRange and activeRecordingStart.
  2. Fetch over the time range:
     - Audio transcript (user narration) — primary source of truth for INTENT
     - OCR text + accessibility events — grounding evidence
     - 5-15 key screenshots at semantic boundaries (app switch, click, scroll burst)
  3. NARRATION IS PRIMARY. If the user says "log into the staging dashboard"
     and opens dashboard.example.com, encode the intent as "log into the
     staging dashboard" — not "navigate to a specific URL". The URL is just
     evidence.
  4. PARAMETER DETECTION: scan narration for variable callouts. Phrases like
     "that's a variable", "call this X", "this part is different each time",
     "my email is X — treat as a parameter" all become entries in the
     parameters list. Replace concrete values with {{param_name}} in
     SKILL.md and flow.json. Also auto-detect obvious parameters (account
     names, emails, file paths) even without explicit callout, but mark them
     "autoDetected": true so the user can confirm or reject in Review.
  5. MODE "retroactive": [timeRange.start, activeRecordingStart) is pre-
     narration. Reconstruct those steps from screen + accessibility alone.
     Tag each such flow.json step with "inferred": true. Add a note at the
     top of SKILL.md flagging those steps for verification. If the user
     narrates retrospectively ("earlier I was opening the dashboard"),
     align that narration with the corresponding past frames.
  6. SLUG: derive from userHints.name if present, else from intent. kebab-case.

OUTPUT to <outputDir>/<slug>/:
  - SKILL.md       (frontmatter `name`, `description`; body sections:
                    `## Intent`, `## Parameters`, `## Steps`)
  - flow.json      (schemaVersion 1; see spec for full schema)
  - frames/*.png   (key screenshots; reference by relative path)

REGENERATION:
  If $MANIFEST_PATH includes a `regenerationContext` field, you are
  regenerating an existing skill. Apply the userFeedback to the new
  output; delete and replace the previousSkillPath atomically.

ON SUCCESS, print exactly one final line to stdout (and nothing after it):
  {"status":"ok","outputDir":"<absolute path>","slug":"<slug>"}
ON FAILURE, print exactly one final line:
  {"status":"error","message":"<one-line reason>"}
