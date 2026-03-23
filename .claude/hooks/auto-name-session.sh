#!/bin/bash
# Auto-name Claude sessions using haiku model.
# Runs on Stop, generates a concise terminal tab title.
# Only fires once per session (marker file prevents re-runs).

json=$(cat)
sid=$(echo "$json" | jq -r '.session_id // empty')
msg=$(echo "$json" | jq -r '.last_assistant_message // empty')

# Need both a session and some content to name
[ -z "$sid" ] || [ -z "$msg" ] && exit 0

# Only name once per session
marker="/tmp/.claude-named-${sid}"
[ -f "$marker" ] && exit 0
touch "$marker"

# Ask haiku for a concise title
title=$(echo "Output ONLY a 3-5 word title (no quotes, no punctuation, no explanation) summarizing this coding session: ${msg:0:400}" \
  | timeout 10 claude -p --model haiku --bare 2>/dev/null \
  | head -1 \
  | sed 's/^["]*//;s/["]*$//' \
  | cut -c1-50)

[ -z "$title" ] && exit 0

# Set terminal tab title
printf '\033]0;%s\007' "$title" > /dev/tty 2>/dev/null || true

exit 0
