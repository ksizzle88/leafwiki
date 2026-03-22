worktree dir `/workspace/wortktrees/{repo-folder}/{feature-name}`

- checkout a new worktree to: the work-tree dir
    - Sparse checkout if possible.
- write a detailed implementation plan to {feature}.md
    -  implement the plan using subagents
- Verify their work.
    - **NEVER** run plan / validate it will not work. 
    - **DO** run terraform fmt to validate syntax
when they are done 
**ALWAYS** prepare a cleanup script that will contian all git actions and close down the worktree. 
    - add required files
    - remove artifacts . plans
    - commit it
    - delete path and remvoe the worktree. 
    
**ALWAYS** rather than making a number of bash tool calls. make one script then run it. to limit user fatigue from input requests. 