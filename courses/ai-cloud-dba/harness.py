#!/usr/bin/env python3
"""Benchmark harness: runs DBA tasks against multiple agent configurations and collects metrics.

Usage:
    python3 harness.py --sample 3            # Run 3 random tasks across all configs (default)
    python3 harness.py --task 01-connect     # Run a specific task across all configs
    python3 harness.py --config cloud        # Run only the cloud config
    python3 harness.py --sample 10           # Run all 10 tasks
    python3 harness.py --dry-run             # Show what would run without executing
"""

import argparse
import json
import os
import random
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import yaml

from evaluator import evaluate_checks, all_checks_passed


COURSE_DIR = Path(__file__).parent
TASKS_DIR = COURSE_DIR / "tasks"
CONFIGS_DIR = COURSE_DIR / "configs"
RESULTS_DIR = COURSE_DIR / "results"
ALL_CONFIGS = ["plain", "skilled", "cloud"]


def load_task(task_path: Path) -> dict:
    """Load a task definition from a YAML file."""
    with open(task_path) as f:
        return yaml.safe_load(f)


def load_all_tasks(task_filter: str | None = None) -> list[dict]:
    """Load all task definitions, optionally filtered by ID prefix."""
    tasks = []
    for path in sorted(TASKS_DIR.glob("*.yaml")):
        task = load_task(path)
        task["_path"] = str(path)
        if task_filter and task_filter not in task["id"]:
            continue
        tasks.append(task)
    return tasks


def invoke_claude(prompt: str, max_turns: int,
                  timeout_seconds: int, cwd: str) -> dict:
    """Invoke the claude CLI and capture results.

    Returns a dict with:
        output: str - The agent's text response
        input_tokens: int - Uncached input tokens
        cache_creation_tokens: int - Cache creation input tokens
        cache_read_tokens: int - Cache read input tokens
        output_tokens: int - Total output tokens consumed
        num_turns: int - Number of agentic turns
        cost_usd: float - Estimated cost in USD
        wall_time: float - Elapsed seconds
        error: str | None - Error message if invocation failed
    """
    cmd = [
        "claude",
        "-p", prompt,
        "--output-format", "json",
        "--max-turns", str(max_turns),
        "--dangerously-skip-permissions",
    ]

    start_time = time.monotonic()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            env={**os.environ},
            cwd=cwd,
        )
        wall_time = time.monotonic() - start_time

        if result.returncode != 0 and not result.stdout.strip():
            return {
                "output": "",
                "input_tokens": 0,
                "cache_creation_tokens": 0,
                "cache_read_tokens": 0,
                "output_tokens": 0,
                "num_turns": 0,
                "cost_usd": 0.0,
                "wall_time": wall_time,
                "error": f"claude exited with code {result.returncode}: {result.stderr.strip()[:500]}",
            }

        # Parse the JSON output from claude CLI
        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            return {
                "output": result.stdout[:2000],
                "input_tokens": 0,
                "cache_creation_tokens": 0,
                "cache_read_tokens": 0,
                "output_tokens": 0,
                "num_turns": 0,
                "cost_usd": 0.0,
                "wall_time": wall_time,
                "error": "Failed to parse claude JSON output",
            }

        # Extract fields from claude's JSON response
        output_text = data.get("result", "")
        usage = data.get("usage", {})
        input_tokens = usage.get("input_tokens", 0)
        cache_creation_tokens = usage.get("cache_creation_input_tokens", 0)
        cache_read_tokens = usage.get("cache_read_input_tokens", 0)
        output_tokens = usage.get("output_tokens", 0)
        num_turns = data.get("num_turns", 0)
        cost_usd = data.get("total_cost_usd", 0.0)

        return {
            "output": output_text,
            "input_tokens": input_tokens,
            "cache_creation_tokens": cache_creation_tokens,
            "cache_read_tokens": cache_read_tokens,
            "output_tokens": output_tokens,
            "num_turns": num_turns,
            "cost_usd": cost_usd,
            "wall_time": wall_time,
            "error": None,
        }

    except subprocess.TimeoutExpired:
        wall_time = time.monotonic() - start_time
        return {
            "output": "",
            "input_tokens": 0,
            "cache_creation_tokens": 0,
            "cache_read_tokens": 0,
            "output_tokens": 0,
            "num_turns": 0,
            "cost_usd": 0.0,
            "wall_time": wall_time,
            "error": f"Timed out after {timeout_seconds}s",
        }
    except FileNotFoundError:
        return {
            "output": "",
            "input_tokens": 0,
            "cache_creation_tokens": 0,
            "cache_read_tokens": 0,
            "output_tokens": 0,
            "num_turns": 0,
            "cost_usd": 0.0,
            "wall_time": 0.0,
            "error": "claude CLI not found in PATH",
        }


def run_benchmark(tasks: list[dict], configs: list[str], num_runs: int,
                  dry_run: bool = False) -> list[dict]:
    """Run all tasks across all configs for the specified number of runs.

    Returns a list of result records.
    """
    results = []
    total = len(tasks) * len(configs) * num_runs
    current = 0

    for task in tasks:
        task_id = task["id"]
        task_name = task["name"]
        max_turns = task.get("max_turns", 20)
        timeout_seconds = task.get("timeout_seconds", 120)
        prompt = task["prompt"]
        checks = task.get("checks", [])

        for config in configs:
            config_dir = str(CONFIGS_DIR / config)

            for run in range(1, num_runs + 1):
                current += 1
                progress = f"[{current}/{total}]"
                print(f"\n{progress} Task: {task_name} | Config: {config} | Run: {run}/{num_runs}")

                if dry_run:
                    print(f"  [DRY RUN] Would invoke claude with prompt ({len(prompt)} chars)")
                    print(f"  [DRY RUN] Agent cwd: {config_dir}")
                    results.append({
                        "task_id": task_id,
                        "task_name": task_name,
                        "config": config,
                        "prompt": prompt.strip(),
                        "run": run,
                        "correct": None,
                        "checks_passed": 0,
                        "checks_total": len(checks),
                        "input_tokens": 0,
                        "cache_creation_tokens": 0,
                        "cache_read_tokens": 0,
                        "output_tokens": 0,
                        "total_tokens": 0,
                        "num_turns": 0,
                        "wall_time": 0.0,
                        "cost_usd": 0.0,
                        "error": "dry run",
                        "agent_output": "",
                        "check_details": [],
                    })
                    continue

                # Invoke claude
                print(f"  Invoking claude (config={config}, max_turns={max_turns}, timeout={timeout_seconds}s)...")
                agent_result = invoke_claude(
                    prompt=prompt,
                    max_turns=max_turns,
                    timeout_seconds=timeout_seconds,
                    cwd=config_dir,
                )

                if agent_result["error"]:
                    print(f"  [ERROR] {agent_result['error']}")

                # Run evaluator checks
                print(f"  Evaluating {len(checks)} check(s)...")
                check_results = evaluate_checks(
                    checks=checks,
                    agent_output=agent_result["output"],
                    cwd=config_dir,
                )

                checks_passed = sum(1 for r in check_results if r.passed)
                correct = all(r.passed for r in check_results) if check_results else False

                for cr in check_results:
                    status = "PASS" if cr.passed else "FAIL"
                    print(f"    [{status}] {cr.description}: {cr.detail}")

                total_tokens = (agent_result["input_tokens"]
                                + agent_result["cache_creation_tokens"]
                                + agent_result["cache_read_tokens"]
                                + agent_result["output_tokens"])
                print(f"  Result: {'CORRECT' if correct else 'INCORRECT'} | "
                      f"Tokens: {total_tokens:,} | "
                      f"Turns: {agent_result['num_turns']} | "
                      f"Time: {agent_result['wall_time']:.1f}s")

                results.append({
                    "task_id": task_id,
                    "task_name": task_name,
                    "config": config,
                    "prompt": prompt.strip(),
                    "run": run,
                    "correct": correct,
                    "checks_passed": checks_passed,
                    "checks_total": len(checks),
                    "input_tokens": agent_result["input_tokens"],
                    "cache_creation_tokens": agent_result["cache_creation_tokens"],
                    "cache_read_tokens": agent_result["cache_read_tokens"],
                    "output_tokens": agent_result["output_tokens"],
                    "total_tokens": total_tokens,
                    "num_turns": agent_result["num_turns"],
                    "wall_time": agent_result["wall_time"],
                    "cost_usd": agent_result["cost_usd"],
                    "error": agent_result["error"],
                    "agent_output": (agent_result["output"] or "")[:500],
                    "check_details": [
                        {
                            "type": cr.check_type,
                            "description": cr.description,
                            "passed": cr.passed,
                            "detail": cr.detail,
                        }
                        for cr in check_results
                    ],
                })

    return results


def save_results(results: list[dict], output_dir: Path) -> Path:
    """Save results to a timestamped JSON file."""
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
    configs_used = sorted(set(r["config"] for r in results))
    suffix = "-".join(configs_used)
    output_path = output_dir / f"run-{timestamp}-{suffix}.json"
    with open(output_path, "w") as f:
        json.dump({
            "timestamp": timestamp,
            "configs": configs_used,
            "num_results": len(results),
            "results": results,
        }, f, indent=2)
    return output_path


def print_report(results: list[dict]):
    """Print a detailed benchmark report with per-config comparison."""
    configs_used = sorted(set(r["config"] for r in results))
    multi_config = len(configs_used) > 1

    print("\n" + "=" * 80)
    print("BENCHMARK REPORT")
    print("=" * 80)

    # Overall summary
    correct_count = sum(1 for r in results if r["correct"])
    total_count = len(results)
    total_tokens = sum(r["total_tokens"] for r in results)
    total_cost = sum(r["cost_usd"] for r in results)

    print(f"\nOverall: {correct_count}/{total_count} tasks passed "
          f"({100 * correct_count / total_count:.0f}% accuracy)")
    print(f"Total tokens: {total_tokens:,}")
    print(f"Total cost: ${total_cost:.4f}")
    print(f"Configs tested: {', '.join(configs_used)}")

    # Per-task detail table
    print(f"\n{'─' * 80}")
    if multi_config:
        print(f"{'Task':<25} {'Config':<10} {'Result':<8} {'Tokens':>10} {'Turns':>6} {'Time':>8}")
    else:
        print(f"{'Task':<30} {'Result':<10} {'Tokens':>10} {'Turns':>6} {'Time':>8}")
    print(f"{'─' * 80}")

    for r in results:
        status = "PASS" if r["correct"] else "FAIL"
        if multi_config:
            print(f"{r['task_name']:<25} {r['config']:<10} {status:<8} "
                  f"{r['total_tokens']:>10,} {r['num_turns']:>6} {r['wall_time']:>7.1f}s")
        else:
            print(f"{r['task_name']:<30} {status:<10} {r['total_tokens']:>10,} "
                  f"{r['num_turns']:>6} {r['wall_time']:>7.1f}s")

    print(f"{'─' * 80}")

    # Comparative summary (only when multiple configs)
    if multi_config:
        print(f"\nCOMPARATIVE SUMMARY")
        print(f"{'─' * 80}")
        print(f"{'Config':<12} {'Accuracy':>10} {'Avg Tokens':>12} {'Avg Turns':>11} {'Avg Time':>10} {'Cost':>10}")
        print(f"{'─' * 80}")

        for config in configs_used:
            cfg_results = [r for r in results if r["config"] == config]
            cfg_correct = sum(1 for r in cfg_results if r["correct"])
            cfg_total = len(cfg_results)
            cfg_tokens = sum(r["total_tokens"] for r in cfg_results)
            cfg_turns = sum(r["num_turns"] for r in cfg_results)
            cfg_time = sum(r["wall_time"] for r in cfg_results)
            cfg_cost = sum(r["cost_usd"] for r in cfg_results)
            accuracy = f"{cfg_correct}/{cfg_total}"
            avg_tokens = cfg_tokens / cfg_total if cfg_total else 0
            avg_turns = cfg_turns / cfg_total if cfg_total else 0
            avg_time = cfg_time / cfg_total if cfg_total else 0
            print(f"{config:<12} {accuracy:>10} {avg_tokens:>12,.0f} {avg_turns:>11.1f} "
                  f"{avg_time:>9.1f}s ${cfg_cost:>8.4f}")

        print(f"{'─' * 80}")

    # Detailed check breakdown
    print(f"\nDETAILED CHECK RESULTS")
    print(f"{'─' * 80}")

    for r in results:
        status = "PASS" if r["correct"] else "FAIL"
        label = f"[{status}] {r['task_name']}"
        if multi_config:
            label += f" ({r['config']})"
        print(f"\n{label}")
        print(f"  Prompt: {r['prompt'][:100]}...")
        for cd in r["check_details"]:
            cs = "PASS" if cd["passed"] else "FAIL"
            print(f"    [{cs}] {cd['description']}: {cd['detail'][:80]}")
        if r["error"]:
            print(f"    [ERROR] {r['error']}")

    print(f"\n{'=' * 80}")


def main():
    # Ensure output is visible immediately (not buffered)
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)

    parser = argparse.ArgumentParser(
        description="Benchmark harness for DBA agent configurations",
    )
    parser.add_argument(
        "--runs", type=int, default=1,
        help="Number of runs per task per config (default: 1)",
    )
    parser.add_argument(
        "--task", type=str, default=None,
        help="Run only tasks matching this ID substring",
    )
    parser.add_argument(
        "--config", type=str, default=None,
        choices=ALL_CONFIGS,
        help="Run only this config (default: all three)",
    )
    parser.add_argument(
        "--output", type=str, default=str(RESULTS_DIR),
        help=f"Output directory for results (default: {RESULTS_DIR})",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would run without executing",
    )
    parser.add_argument(
        "--sample", type=int, default=3,
        help="Randomly sample N tasks from the available set (default: 3)",
    )
    args = parser.parse_args()

    # Determine which configs to run
    configs = [args.config] if args.config else ALL_CONFIGS

    # Validate config directories exist
    for config in configs:
        config_dir = CONFIGS_DIR / config
        if not config_dir.is_dir():
            print(f"Config directory not found: {config_dir}")
            sys.exit(1)

    # Load tasks
    tasks = load_all_tasks(args.task)
    if not tasks:
        print("No tasks found. Check the tasks/ directory.")
        sys.exit(1)

    # Random sampling (skip if a specific task filter was given)
    total_available = len(tasks)
    if args.task is None and args.sample is not None and args.sample < len(tasks):
        tasks = random.sample(tasks, args.sample)

    total_invocations = len(tasks) * len(configs) * args.runs

    print(f"Benchmark configuration:")
    print(f"  Tasks: {len(tasks)} of {total_available} available")
    print(f"  Configs: {', '.join(configs)}")
    print(f"  Runs per task per config: {args.runs}")
    print(f"  Total invocations: {total_invocations}")
    print(f"  Configs directory: {CONFIGS_DIR}")
    print(f"  Output: {args.output}")
    if args.dry_run:
        print(f"  Mode: DRY RUN")
    if args.task is None and args.sample < total_available:
        print(f"  Sampled tasks: {[t['id'] for t in tasks]}")
    print()

    # Run the benchmark
    results = run_benchmark(
        tasks=tasks,
        configs=configs,
        num_runs=args.runs,
        dry_run=args.dry_run,
    )

    # Save results
    output_path = save_results(results, Path(args.output))
    print(f"\nResults saved to: {output_path}")

    # Print detailed report
    print_report(results)


if __name__ == "__main__":
    main()
