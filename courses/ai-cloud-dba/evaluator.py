"""Correctness evaluator for benchmark tasks.

Supports four check types:
- output_contains: Regex match against agent's text response
- sql_query: Run SQL against cluster, compare result to expected value
- file_exists: Check if agent created expected files
- command_check: Run shell command, check exit code or output
"""

import os
import re
import subprocess
from dataclasses import dataclass


@dataclass
class CheckResult:
    """Result of a single correctness check."""
    passed: bool
    check_type: str
    description: str
    detail: str


def evaluate_checks(checks: list[dict], agent_output: str, cwd: str | None = None) -> list[CheckResult]:
    """Run all checks for a task and return results.

    Args:
        checks: List of check definitions from the task YAML.
        agent_output: The full text output from the agent.
        cwd: Working directory for command_check type.

    Returns:
        List of CheckResult objects.
    """
    results = []
    for check in checks:
        check_type = check["type"]
        if check_type == "output_contains":
            results.append(_check_output_contains(check, agent_output))
        elif check_type == "sql_query":
            results.append(_check_sql_query(check))
        elif check_type == "file_exists":
            results.append(_check_file_exists(check, cwd))
        elif check_type == "command_check":
            results.append(_check_command(check, cwd))
        else:
            results.append(CheckResult(
                passed=False,
                check_type=check_type,
                description=check.get("description", "Unknown check"),
                detail=f"Unknown check type: {check_type}",
            ))
    return results


def all_checks_passed(results: list[CheckResult]) -> bool:
    """Return True if all checks passed."""
    return all(r.passed for r in results)


def _check_output_contains(check: dict, agent_output: str) -> CheckResult:
    """Check if agent output matches a regex pattern (case-insensitive)."""
    pattern = check["pattern"]
    description = check.get("description", f"Output matches /{pattern}/")
    try:
        match = re.search(pattern, agent_output, re.IGNORECASE | re.DOTALL)
        if match:
            return CheckResult(
                passed=True,
                check_type="output_contains",
                description=description,
                detail=f"Matched: '{match.group()}'",
            )
        else:
            # Show a truncated snippet of agent output for debugging
            snippet = agent_output[:200] if agent_output else "(empty output)"
            return CheckResult(
                passed=False,
                check_type="output_contains",
                description=description,
                detail=f"Pattern /{pattern}/ not found in output. Start: {snippet}...",
            )
    except re.error as e:
        return CheckResult(
            passed=False,
            check_type="output_contains",
            description=description,
            detail=f"Invalid regex pattern: {e}",
        )


def _check_sql_query(check: dict) -> CheckResult:
    """Run a SQL query and compare the result to an expected value."""
    query = check["query"]
    description = check.get("description", f"SQL check: {query[:60]}")

    # Prefer CRDB_URL (full connection URL, works with CockroachDB Cloud)
    crdb_url = os.environ.get("CRDB_URL", "")

    if crdb_url:
        cmd = ["cockroach", "sql", f"--url={crdb_url}", "--format=csv", "-e", query]
    else:
        # Fallback to host/port/certs for self-hosted clusters
        host = os.environ.get("CRDB_HOST", "localhost")
        port = os.environ.get("CRDB_PORT", "26257")
        certs_dir = os.environ.get("CRDB_CERTS_DIR", "")
        cmd = ["cockroach", "sql", f"--host={host}:{port}", "--format=csv", "-e", query]
        if certs_dir:
            cmd.append(f"--certs-dir={certs_dir}")
        else:
            cmd.append("--insecure")

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return CheckResult(
                passed=False,
                check_type="sql_query",
                description=description,
                detail=f"SQL error: {result.stderr.strip()}",
            )

        # Parse CSV output: skip header, get the value from the last line
        lines = [l.strip() for l in result.stdout.strip().splitlines() if l.strip()]
        if len(lines) < 2:
            actual = "0"
        else:
            actual = lines[-1].strip()

        # Support different comparison modes
        if "expected" in check:
            expected = str(check["expected"]).strip()
            passed = actual == expected
            detail = f"Expected '{expected}', got '{actual}'"
        elif "expected_ge" in check:
            try:
                passed = int(actual) >= int(check["expected_ge"])
                detail = f"Expected >= {check['expected_ge']}, got '{actual}'"
            except ValueError:
                passed = False
                detail = f"Cannot compare: expected >= {check['expected_ge']}, got '{actual}'"
        elif "expected_gt" in check:
            try:
                passed = int(actual) > int(check["expected_gt"])
                detail = f"Expected > {check['expected_gt']}, got '{actual}'"
            except ValueError:
                passed = False
                detail = f"Cannot compare: expected > {check['expected_gt']}, got '{actual}'"
        else:
            passed = False
            detail = "No expected value specified in check"

        return CheckResult(
            passed=passed,
            check_type="sql_query",
            description=description,
            detail=detail,
        )
    except subprocess.TimeoutExpired:
        return CheckResult(
            passed=False,
            check_type="sql_query",
            description=description,
            detail="SQL query timed out after 30s",
        )
    except FileNotFoundError:
        return CheckResult(
            passed=False,
            check_type="sql_query",
            description=description,
            detail="cockroach binary not found in PATH",
        )


def _check_file_exists(check: dict, cwd: str | None) -> CheckResult:
    """Check if a file exists at the specified path."""
    path = check["path"]
    description = check.get("description", f"File exists: {path}")

    if cwd and not os.path.isabs(path):
        path = os.path.join(cwd, path)

    exists = os.path.exists(path)
    return CheckResult(
        passed=exists,
        check_type="file_exists",
        description=description,
        detail=f"{'Found' if exists else 'Not found'}: {path}",
    )


def _check_command(check: dict, cwd: str | None) -> CheckResult:
    """Run a shell command and check exit code or output."""
    command = check["command"]
    description = check.get("description", f"Command check: {command[:60]}")

    try:
        result = subprocess.run(
            command, shell=True, capture_output=True, text=True,
            timeout=30, cwd=cwd,
            env={**os.environ},
        )

        if "expected_exit_code" in check:
            expected = int(check["expected_exit_code"])
            passed = result.returncode == expected
            detail = f"Exit code: expected {expected}, got {result.returncode}"
        elif "expected_output" in check:
            expected = str(check["expected_output"]).strip()
            actual = result.stdout.strip()
            passed = expected in actual
            detail = f"Expected '{expected}' in output, got '{actual[:200]}'"
        else:
            passed = result.returncode == 0
            detail = f"Exit code: {result.returncode}"

        return CheckResult(
            passed=passed,
            check_type="command_check",
            description=description,
            detail=detail,
        )
    except subprocess.TimeoutExpired:
        return CheckResult(
            passed=False,
            check_type="command_check",
            description=description,
            detail=f"Command timed out after 30s: {command}",
        )
