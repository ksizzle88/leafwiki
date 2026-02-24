# Parallel Exploration Skill

## What This Skill Does

Runs multiple Claude agents in parallel to explore different approaches to a problem, then combines the best ideas into a final solution.

## When to Use

Use this skill when:
- **Multiple viable approaches** exist for solving a problem
- **Parallel exploration** would reveal trade-offs faster than sequential testing
- **Comparative analysis** would help make better decisions
- **Time is limited** and you want to explore options simultaneously

## Common Use Cases

- Architecture decisions (microservices vs monolith, SQL vs NoSQL, etc.)
- Configuration strategies (Docker setups, CI/CD pipelines, deployment patterns)
- Code refactoring approaches (different design patterns, restructuring strategies)
- Feature implementation options (different UI frameworks, API designs, etc.)
- Technology evaluations (comparing libraries, frameworks, tools)

## How It Works

1. **Setup**: Creates exploration folder with approach subfolders (a, b, c, etc.)
2. **Parallel Execution**: Spawns separate Claude agents for each approach using the Task tool
3. **Documentation**: Each agent documents findings in its approach folder
4. **Combination**: Final agent reviews all approaches and creates best solution
5. **Decision**: Documents rationale for final decision

## Usage

### Basic Usage

```
/parallel-exploration
```

Claude will ask you:
- What problem you're exploring
- How many approaches to test (2-10)
- Goal for each approach
- Base directory to work from (optional)

### Advanced Usage

Provide goals upfront:

```
/parallel-exploration "docker configuration strategy" 3 \
  "Approach A: Docker-compose override pattern" \
  "Approach B: Dockerfile.local with multi-stage builds" \
  "Approach C: Minimal devcontainer.json changes"
```

## Workflow

### Phase 1: Setup (Automated)
- Creates `exploration/` folder in current or specified directory
- Creates approach subfolders (a/, b/, c/, etc.)
- Copies base files if needed
- Creates documentation templates

### Phase 2: Parallel Exploration (Automated)
- Launches Task agents for each approach simultaneously
- Each agent works independently in its folder
- Progress logged to `exploration/logs/`
- Runs until all approaches complete

### Phase 3: Combination (Automated)
- Spawns final agent to review all approaches
- Agent reads all approach documentation
- Creates `best-plan/` with optimal solution
- Documents decision rationale

### Phase 4: Review (Manual)
- Review `exploration/best-plan/README.md` for final decision
- Review individual approach folders for details
- Apply chosen solution to your project

## Output Structure

```
exploration/
├── EXPLORATION.md          # Overview and goals
├── a/                      # Approach A
│   ├── README.md          # Findings and documentation
│   └── (work files)
├── b/                      # Approach B
│   ├── README.md
│   └── (work files)
├── c/                      # Approach C
│   ├── README.md
│   └── (work files)
├── logs/                   # Execution logs
│   ├── approach-a.log
│   ├── approach-b.log
│   └── approach-c.log
└── best-plan/             # Final solution
    ├── README.md          # Decision and rationale
    ├── TASK.md            # Combination instructions
    ├── .approach-docs/    # Reference docs
    └── (final solution)
```

## Examples

### Example 1: Docker Configuration Strategy

```
Problem: How should we integrate Claudio into 7 different repositories?

Approaches:
- A: Docker-compose override files
- B: Dockerfile.local with shared volumes
- C: Minimal devcontainer.json snippets

Result: Combination of B and C - use Dockerfile.local for complex projects, snippets for simple ones
```

### Example 2: API Architecture

```
Problem: Should we use REST, GraphQL, or gRPC for our new API?

Approaches:
- A: REST with OpenAPI
- B: GraphQL with Apollo
- C: gRPC with Protocol Buffers

Result: GraphQL for external API, gRPC for internal services
```

### Example 3: Database Migration Strategy

```
Problem: How should we migrate from MongoDB to PostgreSQL?

Approaches:
- A: Big bang migration
- B: Gradual dual-write strategy
- C: Event sourcing with CQRS

Result: Approach B with modifications from C for critical tables
```

## Parameters

- **problem**: Description of what you're exploring (required)
- **approach_count**: Number of parallel approaches (2-10, default: 3)
- **goals**: Goal/strategy for each approach (optional, will prompt if not provided)
- **base_dir**: Directory to work from (optional, defaults to current directory)
- **base_files**: Files/folders to copy to each approach (optional)

## Tips

### Defining Good Approaches

Each approach should be:
- **Distinct**: Meaningfully different from other approaches
- **Viable**: Could realistically work as a solution
- **Testable**: Can be evaluated within time constraints
- **Documented**: Easy to compare with others

### Writing Effective Goals

Good approach goals:
- ✅ "Focus on docker-compose override pattern for zero repo changes"
- ✅ "Minimize configuration duplication using templates"
- ✅ "Maximize portability across Windows/Mac/Linux"

Poor approach goals:
- ❌ "Make it work" (too vague)
- ❌ "Try different things" (not specific enough)
- ❌ "Use the best approach" (defeats purpose of exploration)

### Monitoring Progress

While approaches run, check logs:
```bash
tail -f exploration/logs/approach-a.log
tail -f exploration/logs/approach-b.log
tail -f exploration/logs/approach-c.log
```

### Cancelling Execution

The skill tracks agent IDs. If you need to cancel:
- Ctrl+C in the terminal
- Or use `/tasks` to see running tasks and kill them

## Limitations

- Maximum 10 parallel approaches (to avoid resource issues)
- Each approach agent has standard token/turn limits
- Agents work independently (no communication between approaches)
- Combination step requires all approaches to complete
- Works best with problems that have clear evaluation criteria

## Advanced: Custom Base Files

To copy base files to each approach:

```javascript
{
  "base_files": [
    "src/**/*.ts",
    "package.json",
    "tsconfig.json"
  ]
}
```

## Advanced: Custom Evaluation Criteria

Provide evaluation criteria for the combination step:

```
Focus on:
1. Maintainability (most important)
2. Performance (important)
3. Developer experience (nice to have)
```

## Related Skills

- `/plan-feature` - For planning implementation (single approach)
- `/code-review` - For reviewing completed code
- `/validation:review-execution` - For post-implementation review

## Output

After completion, the skill provides:
- Path to exploration folder
- Summary of all approaches
- Link to final decision (best-plan/README.md)
- Next steps for applying the solution
