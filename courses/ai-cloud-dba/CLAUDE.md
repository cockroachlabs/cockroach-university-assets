# AI Cloud DBA — Multi-Config Benchmark Runner

You are helping a learner benchmark an AI DBA agent called **Ladybug** across three different agent configurations to compare how knowledge sources affect accuracy and token usage.

## Agent Configurations

The `configs/` directory contains three agent setups, each with a different knowledge source:

| Config | CLAUDE.md | Skills | MCP Server | Description |
|--------|-----------|--------|------------|-------------|
| `plain` | None | None | None | Bare model — no domain knowledge, no tools |
| `skilled` | Ladybug persona | 103 skill files | None | Agent with CockroachDB skill files for reference |
| `cloud` | Ladybug persona | None | Cloud MCP | Agent with live cluster access via Cloud MCP server |

- **plain** — Tests what the base model knows about CockroachDB without any guidance
- **skilled** — Tests whether skill files (static documentation) improve accuracy
- **cloud** — Tests whether live cluster access via MCP tools improves accuracy

## Available Tasks

| ID | Name | Domain |
|----|------|--------|
| 01 | Connect to Cluster | Cluster Operations |
| 02 | Check Cluster Health | Monitoring |
| 03 | Diagnose Slow Reads | SQL Performance |
| 07 | Refuse DROP TABLE | Safety |
| 09 | Explain a Query Plan | SQL Performance |
| 12 | Review Cluster Settings | Cluster Configuration |
| 18 | Find Unused Indexes | SQL Performance |
| 20 | Check Replication Health | Monitoring |
| 21 | Refuse Privilege Escalation | Safety |
| 24 | Check Cluster Version | Cluster Operations |

## How to Run the Benchmark

Run 3 random tasks across all 3 configs (default):

    python3 harness.py

Run all 10 tasks across all configs:

    python3 harness.py --sample 10

Run a single config only:

    python3 harness.py --config cloud

Run a specific task across all configs:

    python3 harness.py --task 01-connect

Run a single config and task:

    python3 harness.py --config cloud --task 01-connect

Dry run (show what would execute):

    python3 harness.py --dry-run

## Interpreting Results

The report shows for each task and config:
- **PASS/FAIL** — whether the agent's response passed all correctness checks
- **Tokens** — total tokens consumed (input + cache + output)
- **Turns** — number of agentic turns (tool calls) the agent made
- **Time** — wall clock time for the task

When multiple configs are tested, a **COMPARATIVE SUMMARY** table shows per-config accuracy, average tokens, average turns, average time, and cost.

## Key Files

- `harness.py` — Benchmark runner (invoke this)
- `evaluator.py` — Check engine (output_contains, sql_query, command_check, file_exists)
- `tasks/*.yaml` — Task definitions with prompts and checks
- `configs/plain/` — Empty directory (bare model, no CLAUDE.md)
- `configs/skilled/CLAUDE.md` — Ladybug persona with skill file references
- `configs/skilled/skills/` — 103 CockroachDB skill files
- `configs/cloud/CLAUDE.md` — Ladybug persona with Cloud MCP guidance
- `configs/cloud/.claude.json` — Cloud MCP server configuration (learner must configure API key)
