#!/bin/bash
# Save last Claude response to /tmp/claude-last.md on every Stop.
# Use: ! code /tmp/claude-last.md  (or the alias: ! open-last)
jq -r '.last_assistant_message // empty' > /tmp/claude-last.md 2>/dev/null
exit 0
