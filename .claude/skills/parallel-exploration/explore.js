#!/usr/bin/env node

/**
 * Parallel Exploration Skill - Implementation
 *
 * Spawns multiple Claude agents in parallel to explore different approaches,
 * then combines the results into a best solution.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Parse command line arguments
const args = process.argv.slice(2);

const config = {
  problem: args[0] || 'Undefined problem',
  approachCount: parseInt(args[1]) || 3,
  goals: args.slice(2, 2 + (parseInt(args[1]) || 3)),
  baseDir: process.cwd(),
  explorationDir: null
};

// Validate
if (config.approachCount < 2 || config.approachCount > 10) {
  console.error('Error: Approach count must be between 2 and 10');
  process.exit(1);
}

if (config.goals.length === 0) {
  console.error('Error: Must provide goals for each approach');
  console.error(`Usage: node explore.js "problem" <count> "goal1" "goal2" ... "goalN"`);
  process.exit(1);
}

if (config.goals.length !== config.approachCount) {
  console.error(`Error: Expected ${config.approachCount} goals, got ${config.goals.length}`);
  process.exit(1);
}

// Create exploration structure
function createExplorationStructure() {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').split('T')[0];
  const safeProblem = config.problem.toLowerCase().replace(/[^a-z0-9]+/g, '-').substring(0, 30);
  const explorationName = `exploration-${safeProblem}-${timestamp}`;

  config.explorationDir = path.join(config.baseDir, explorationName);

  console.log(`Creating exploration: ${explorationName}`);

  fs.mkdirSync(config.explorationDir, { recursive: true });
  fs.mkdirSync(path.join(config.explorationDir, 'logs'), { recursive: true });

  // Create EXPLORATION.md
  const explorationDoc = `# ${config.problem}

## Exploration Overview

**Created**: ${new Date().toISOString()}
**Approaches**: ${config.approachCount}
**Base Directory**: ${config.baseDir}

## Approaches

${config.goals.map((goal, i) => {
  const letter = String.fromCharCode(97 + i); // a, b, c...
  return `### Approach ${letter.toUpperCase()}\n**Goal**: ${goal}\n**Status**: In Progress\n**Folder**: \`${letter}/\``;
}).join('\n\n')}

## Timeline

- **Started**: ${new Date().toLocaleString()}
- **Parallel Execution**: In progress...
- **Combination**: Pending
- **Completed**: Pending

## Next Steps

1. Monitor progress: \`tail -f logs/*.log\`
2. Review approaches when complete
3. Review best-plan for final decision
`;

  fs.writeFileSync(
    path.join(config.explorationDir, 'EXPLORATION.md'),
    explorationDoc
  );

  // Create approach folders
  for (let i = 0; i < config.approachCount; i++) {
    const letter = String.fromCharCode(97 + i);
    const approachDir = path.join(config.explorationDir, letter);

    fs.mkdirSync(approachDir, { recursive: true });

    // Create README template
    const readme = `# Approach ${letter.toUpperCase()}

## Goal

${config.goals[i]}

## Strategy

[Document your technical approach here]

## Key Decisions

[Document important decisions and trade-offs]

## Implementation

[Document what you implemented or designed]

## Pros

[List advantages of this approach]

## Cons

[List disadvantages and limitations]

## Results

[Document outcomes and findings]

---

**Started**: ${new Date().toLocaleString()}
**Status**: In Progress
`;

    fs.writeFileSync(
      path.join(approachDir, 'README.md'),
      readme
    );
  }

  console.log(`✓ Exploration structure created at: ${config.explorationDir}`);
  return config.explorationDir;
}

// Generate agent task IDs file for tracking
function createAgentTracker() {
  const trackerPath = path.join(config.explorationDir, '.agent-tasks.json');
  fs.writeFileSync(trackerPath, JSON.stringify({
    approaches: [],
    combiner: null,
    startTime: new Date().toISOString()
  }, null, 2));
  return trackerPath;
}

// Main execution
async function main() {
  console.log('==========================================');
  console.log('Parallel Exploration Skill');
  console.log('==========================================');
  console.log('');
  console.log(`Problem: ${config.problem}`);
  console.log(`Approaches: ${config.approachCount}`);
  console.log('');

  // Create structure
  createExplorationStructure();
  createAgentTracker();

  console.log('');
  console.log('==========================================');
  console.log('Exploration Ready');
  console.log('==========================================');
  console.log('');
  console.log('The exploration structure has been created.');
  console.log('');
  console.log('IMPORTANT: Due to Claude CLI limitations, parallel execution');
  console.log('must be handled by the calling Claude instance using the Task tool.');
  console.log('');
  console.log('Recommended next steps:');
  console.log('');
  console.log('1. Use Task tool to spawn agents for each approach:');
  for (let i = 0; i < config.approachCount; i++) {
    const letter = String.fromCharCode(97 + i);
    console.log(`   - Task(general-purpose): Work in ${letter}/ - ${config.goals[i]}`);
  }
  console.log('');
  console.log('2. After all complete, spawn combiner agent:');
  console.log('   - Task(general-purpose): Review all approaches and create best-plan/');
  console.log('');
  console.log(`Exploration directory: ${config.explorationDir}`);
  console.log('');

  // Output structured data for Claude to parse
  console.log('---EXPLORATION-DATA-START---');
  console.log(JSON.stringify({
    explorationDir: config.explorationDir,
    approachCount: config.approachCount,
    approaches: config.goals.map((goal, i) => ({
      letter: String.fromCharCode(97 + i),
      goal: goal,
      directory: path.join(config.explorationDir, String.fromCharCode(97 + i))
    })),
    logsDir: path.join(config.explorationDir, 'logs')
  }, null, 2));
  console.log('---EXPLORATION-DATA-END---');
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
