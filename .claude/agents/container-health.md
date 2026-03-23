---
name: container-health
description: Report on container resource usage, top processes, and bloated extensions
model: haiku
tools:
  - Bash
  - Read
  - Write
---

# Container Health Report

Generate a resource usage report for all running containers.

## Steps

1. Run `docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}"` to get container-level stats
2. For each container using more than 500 MB, run `docker exec <name> ps aux --sort=-%mem | head -15` to find top processes
3. Flag any process using more than 200 MB RSS that looks like an idle language server or extension
4. Summarize findings as a table:
   - Container name
   - Total memory
   - Top 3 memory consumers (process name + RSS)
   - Recommendations (e.g. "remove unused extension X")

## Output format

```
## Container Health Report (date)

### Summary
| Container | Memory | CPU | Status |
|-----------|--------|-----|--------|

### Details
(per container with high memory, list top processes and recommendations)
```

Keep it concise. Focus on actionable findings — things that can be disabled or removed to save resources.
