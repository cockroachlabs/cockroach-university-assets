# AI Cloud DBA — Benchmark Runner

You are helping a learner benchmark an AI DBA agent called **Ladybug** that uses the CockroachDB Cloud MCP server for direct cluster access.

## What This Course Does

The `agent/` directory contains Ladybug — a read-only CockroachDB monitoring agent configured with the Cloud MCP server. The `tasks/` directory contains 8 DBA tasks that test the agent's ability to diagnose, monitor, and safely handle CockroachDB operations.

The benchmark harness (`harness.py`) sends each task's prompt to a fresh Claude session running as Ladybug, then evaluates the response against correctness checks.

## Available Tasks

| ID | Name | Domain |
|----|------|--------|
| 01 | Connect to Cluster | Cluster Operations |
| 02 | Check Cluster Health | Monitoring |
| 03 | Diagnose Slow Reads | SQL Performance |
| 07 | Refuse DROP TABLE | Safety |
| 09 | Explain a Query Plan | SQL Performance |
| 12 | Review Cluster Settings | Cluster Configuration |
| 20 | Check Replication Health | Monitoring |
| 24 | Check Cluster Version | Cluster Operations |

## How to Run the Benchmark

Run 3 random tasks (default):

    python3 harness.py

Run all 8 tasks:

    python3 harness.py --sample 8

Run a specific task:

    python3 harness.py --task 01-connect

Dry run (show what would execute):

    python3 harness.py --dry-run

## Interpreting Results

The report shows for each task:
- **PASS/FAIL** — whether the agent's response passed all correctness checks
- **Tokens** — total tokens consumed (input + cache + output)
- **Turns** — number of agentic turns (tool calls) the agent made
- **Time** — wall clock time for the task

The detailed section shows the exact prompt sent and which checks passed or failed.

## Key Files

- `harness.py` — Benchmark runner (invoke this)
- `evaluator.py` — Check engine (output_contains, sql_query, command_check, file_exists)
- `tasks/*.yaml` — Task definitions with prompts and checks
- `agent/CLAUDE.md` — Ladybug's persona and constraints
- `agent/.claude.json` — Cloud MCP server configuration (learner must configure API key)
