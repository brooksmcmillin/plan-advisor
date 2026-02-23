#!/usr/bin/env bash
# analyze-plan.sh
# PostToolUse hook for Write tool - analyzes plan files and advises on
# whether to clear context before execution.
#
# Input: JSON on stdin from Claude Code PostToolUse event
# Output: Advisory message on stdout (shown in transcript mode)
#         Exit 0 = non-blocking, advisory only
#
# Requires: jq, claude CLI

set -euo pipefail

# Read the PostToolUse JSON payload from stdin
INPUT=$(cat)

# Extract the file path from the tool input
# PostToolUse Write payload has tool_input.file_path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Gate: only analyze files in .claude/plans/ directories
if [[ "$FILE_PATH" != *".claude/plans/"* ]]; then
    exit 0
fi

# Verify the file exists and is readable
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Read plan contents
PLAN_CONTENT=$(cat "$FILE_PATH")

# Count approximate metrics for the analysis prompt
LINE_COUNT=$(echo "$PLAN_CONTENT" | wc -l)
WORD_COUNT=$(echo "$PLAN_CONTENT" | wc -w)

# Extract context usage from the hook payload if available
CONTEXT_PCT=$(echo "$INPUT" | jq -r '.session.context_window_usage // empty' 2>/dev/null)

# Build the analysis prompt
ANALYSIS_PROMPT="You are a Claude Code plan advisor. A plan file was just created at: $FILE_PATH

Plan stats: $LINE_COUNT lines, $WORD_COUNT words
$(if [[ -n "${CONTEXT_PCT:-}" ]]; then echo "Current context usage: $CONTEXT_PCT"; else echo "Context usage: unknown (assume moderate)"; fi)

Here is the plan content:
---
$PLAN_CONTENT
---

Analyze this plan and give a SHORT recommendation (3-4 sentences max) on whether the user should:
1. Clear context and auto-accept (best when plan is detailed and self-contained)
2. Keep context and auto-accept (best when plan is a sketch that needs conversational context)
3. Keep context and manually approve (best when plan touches risky areas or is ambiguous)

Consider:
- Is the plan self-contained? Could someone execute it without any prior conversation?
- How many files will likely be touched? More files = more context needed for execution.
- Are there ambiguous decisions that relied on earlier conversation?
- Is the plan doing anything risky (deleting files, modifying configs, etc.)?

Output ONLY your recommendation. No preamble. Start with your pick (e.g., 'Recommendation: Clear context (option 1)') then briefly explain why."

# Spawn a sub-agent using claude CLI in print mode (non-interactive, one-shot)
# Using --model sonnet for speed/cost efficiency on this advisory task
ADVICE=$(echo "$ANALYSIS_PROMPT" | claude --print --model sonnet 2>/dev/null) || {
    # If claude CLI fails, fall back to a simple heuristic
    if [[ $WORD_COUNT -gt 500 && $LINE_COUNT -gt 30 ]]; then
        ADVICE="Recommendation: Clear context (option 1). This plan is detailed ($LINE_COUNT lines, $WORD_COUNT words) and likely self-contained enough to survive a context clear."
    elif [[ $WORD_COUNT -lt 150 ]]; then
        ADVICE="Recommendation: Keep context (option 2). This plan is short ($WORD_COUNT words) and may rely on conversational context not captured in the plan."
    else
        ADVICE="Recommendation: Keep context, manually approve (option 3). This plan is moderate length - review the execution steps before auto-accepting."
    fi
}

# Output the advice - this gets shown in transcript mode (Ctrl+R)
echo ""
echo "Plan Advisor"
echo "---"
echo "$ADVICE"
echo "---"

exit 0
