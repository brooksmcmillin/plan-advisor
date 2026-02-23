# Plan Advisor

A Claude Code hook that analyzes plan files when they're created and recommends whether you should clear context, preserve it, or manually approve edits before execution.

## What it does

When Claude Code writes a plan file to `.claude/plans/`, this hook:

1. Detects the write via a `PostToolUse` hook on the `Write` tool
2. Checks if the file path matches `.claude/plans/*` (skips everything else)
3. Sends the plan to `claude --print` for analysis
4. Outputs a recommendation in the transcript

The analysis evaluates:
- **Self-containedness**: Can this plan be executed without prior conversation context?
- **Scope**: How many files will be touched? Is the scope large enough to warrant context clearing?
- **Ambiguity**: Are there decisions that depend on earlier conversational context?
- **Risk**: Does the plan modify configs, delete files, or touch sensitive areas?

If the `claude` CLI isn't available or fails, it falls back to a simple heuristic based on plan length.

## Requirements

- `jq` (for parsing the hook's JSON payload)
- `claude` CLI on PATH (for sub-agent analysis; falls back to heuristics if unavailable)

## Installation

In Claude Code, run:

```
/plugin marketplace add brooksmcmillin/plan-advisor
/plugin install plan-advisor@brooksmcmillin-plan-advisor
```

### Manual installation

If you prefer not to use the plugin system, clone the repo and add the hook to your settings directly.

Clone the repo:

```bash
git clone https://github.com/brooksmcmillin/plan-advisor.git \
  ~/.claude/plugins/plan-advisor
```

Then add the hook to `~/.claude/settings.json` (global) or `.claude/settings.json` (per-project):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/plugins/plan-advisor/scripts/analyze-plan.sh",
            "timeout": 45
          }
        ]
      }
    ]
  }
}
```

Adjust the path if you cloned the repo elsewhere.

## Configuration

No configuration needed. The hook fires automatically on any `Write` to a `.claude/plans/` path and silently exits for everything else.

The sub-agent runs with `--model sonnet` for speed. Edit `scripts/analyze-plan.sh` to change this.

## How it works

```
Write tool fires -> PostToolUse hook triggers
  -> analyze-plan.sh reads stdin JSON
  -> checks if file path matches .claude/plans/*
  -> if yes: reads plan, sends to claude --print for analysis
  -> outputs recommendation to stdout (visible in transcript)
```

## Testing

```bash
# Create a test plan file
mkdir -p /tmp/test/.claude/plans
cat > /tmp/test/.claude/plans/test.md << 'EOF'
# Plan: Refactor auth module
1. Move auth logic from utils.py to auth/service.py
2. Update imports in 5 files
3. Add tests for new module
EOF

# Test with a plan file (should produce analysis output)
echo '{"tool_input":{"file_path":"/tmp/test/.claude/plans/test.md"}}' | \
  bash scripts/analyze-plan.sh

# Test with a non-plan file (should exit silently)
echo '{"tool_input":{"file_path":"/src/main.py"}}' | \
  bash scripts/analyze-plan.sh

# Test the heuristic fallback (hide claude from PATH)
env PATH=/usr/bin:/bin \
  bash -c 'echo "{\"tool_input\":{\"file_path\":\"/tmp/test/.claude/plans/test.md\"}}" | bash scripts/analyze-plan.sh'
```

For a full integration test, install the hook per the instructions above, then ask Claude Code to create a plan. The hook fires automatically and the output appears in transcript mode (`Ctrl+R`).

## Limitations

- **Context % not reliably available**: The PostToolUse payload may not include current context window usage. The sub-agent works without it but can't factor it into recommendations.
- **PostToolUse payload schema**: The exact JSON shape for `tool_input.file_path` may vary across Claude Code versions. The script tries both `file_path` and `filePath`.
- **Token cost**: Each plan analysis costs ~1-2k tokens (Sonnet). In practice plan creation is infrequent.
- **Transcript visibility**: Output shows in transcript mode (`Ctrl+R`), not inline in the main conversation. This is a limitation of exit code 0 hooks.

## License

MIT
