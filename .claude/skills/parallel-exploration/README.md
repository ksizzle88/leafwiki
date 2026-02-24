# Parallel Exploration Skill

## Quick Start

```
Can you use the parallel-exploration skill to explore:
- Problem: "Docker configuration strategy for 7 repositories"
- Approach A: "Docker-compose override pattern"
- Approach B: "Dockerfile.local with multi-stage builds"
- Approach C: "Minimal devcontainer.json snippets"
```

## What This Does

1. Creates exploration folder structure with approach subfolders
2. Spawns **parallel Task agents** for each approach (using Claude's Task tool)
3. Each agent works independently and documents findings
4. After all complete, spawns combiner agent to create best-plan
5. Returns path to final decision

## How Claude Should Use This

When you invoke this skill, Claude should:

1. **Run explore.js** to create folder structure
2. **Parse the JSON output** between `---EXPLORATION-DATA-START---` and `---EXPLORATION-DATA-END---`
3. **Use Task tool in PARALLEL** to spawn agents:
   ```javascript
   // In a SINGLE message with multiple Task tool calls
   Task(general-purpose, "Approach A exploration", "Work in exploration-xxx/a/ folder. Goal: [goal A]. Document findings in README.md")
   Task(general-purpose, "Approach B exploration", "Work in exploration-xxx/b/ folder. Goal: [goal B]. Document findings in README.md")
   Task(general-purpose, "Approach C exploration", "Work in exploration-xxx/c/ folder. Goal: [goal C]. Document findings in README.md")
   ```
4. **Wait for all to complete** (they run in parallel automatically)
5. **Spawn combiner agent**:
   ```javascript
   Task(general-purpose, "Combine approaches", "Review all approaches in exploration-xxx/ and create best-plan/ folder with optimal solution")
   ```
6. **Report results** to user with path to best-plan/README.md

## Arguments

- **problem**: Description of what you're exploring
- **count**: Number of approaches (2-10)
- **goal1, goal2, ...**: Goal for each approach

## Example Usage

User: "Can you use parallel-exploration to test 3 different API design approaches?"

Claude should:
1. Ask for the problem description and goals if not provided
2. Run: `node explore.js "API design approach" 3 "REST with OpenAPI" "GraphQL with Apollo" "gRPC with Protocol Buffers"`
3. Parse output to get exploration directory
4. Spawn 3 Task agents in parallel (single message with 3 Task calls)
5. Wait for completion
6. Spawn combiner agent
7. Show user the final decision

## Output Structure

```
exploration-{problem}-{date}/
├── EXPLORATION.md           # Overview
├── .agent-tasks.json        # Agent tracking
├── a/
│   └── README.md           # Approach A findings
├── b/
│   └── README.md           # Approach B findings
├── c/
│   └── README.md           # Approach C findings
├── logs/                    # (created by agents)
└── best-plan/              # (created by combiner)
    └── README.md           # Final decision
```

## Important Notes

- **Use Task tool, not bash backgrounding** - Task tool properly parallelizes
- **Single message for parallel tasks** - Send one message with multiple Task calls
- **Wait for all agents** - Don't spawn combiner until all approaches complete
- **Parse JSON output** - Use the structured data between markers
- **Report to user** - Show path to best-plan/README.md when done
