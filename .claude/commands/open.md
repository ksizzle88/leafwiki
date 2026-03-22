# /open - Open last response in VS Code

Take your most recent response and open it in VS Code as a markdown file.

## Steps

1. Write your last response (the message immediately before the user typed `/open`) to a temp file at `/tmp/claude-<timestamp>.md` using the Write tool
2. Run `code /tmp/claude-<timestamp>.md` to open it in VS Code
3. Tell the user the file is open

Use the current epoch seconds for `<timestamp>` (e.g., `/tmp/claude-1711234567.md`).

Write the content exactly as it appeared -- do not summarize or modify it. If the response contained code blocks, keep them. Preserve all formatting.

If the user provides an argument (e.g., `/open summary`), use that as a hint for what to include -- but default to the full last response.
