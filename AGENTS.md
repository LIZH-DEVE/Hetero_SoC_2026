# AGENTS.md

## Mandatory Workflow

For every user request in this repository, you must use the Superpower skills before taking action.

Required baseline order:
1. Use `using-superpowers`
2. Determine which additional Superpower skills apply
3. State which skill(s) you are using and why before substantial action

## Required Skills By Task Type

- Design, feature work, behavior change, implementation planning:
  - `brainstorming`
- Bug, regression, unexpected behavior, failing tests:
  - `systematic-debugging`
- Any code change or bugfix implementation:
  - `test-driven-development`
- Before claiming work is complete, fixed, or passing:
  - `verification-before-completion`
- When multiple independent tasks can run in parallel:
  - `dispatching-parallel-agents`
- When implementing a written plan with parallel workers:
  - `subagent-driven-development`

## Hard Rules

- Do not skip skills because the task looks simple.
- Do not answer first and use skills later.
- Do not start implementation before the required skill workflow is followed.
- If multiple skills apply, use all relevant ones in the correct order.
- Before any substantial tool call, file edit, or code change, explicitly state which skill(s) are being used.
- If a required skill cannot be used cleanly, say so explicitly and explain the fallback.

## User Override

- Direct user instructions override default workflow choices, but do not cancel the requirement to use applicable Superpower skills unless the user explicitly says not to use them.

## Practical Reminder

- "Simple question", "quick check", "small patch", and "just inspect this" still count as tasks.
- Repository-local instructions in `AGENTS.md` must be followed on every turn.
