#!/usr/bin/env python3
"""
RAG-powered troubleshooting assistant for CockroachDB operations.

Takes a symptom description, embeds it, performs hybrid vector + metadata
search against the opsrag database, follows prerequisite chains, and
returns structured troubleshooting guidance.

Usage:
    python3 troubleshoot.py "node is unresponsive after maintenance window"
    python3 troubleshoot.py "backup is running too slowly"
    python3 troubleshoot.py --domain "Cluster Maintenance" "under-replicated ranges"
"""

import sys
import argparse
import psycopg2
import psycopg2.extras
from embeddings import embed, vector_to_sql


DB_URL = "postgresql://root@localhost:26257/opsrag?sslmode=require&sslrootcert=/root/certs/ca.crt&sslcert=/root/certs/client.root.crt&sslkey=/root/certs/client.root.key"


def connect():
    """Connect to the opsrag database."""
    return psycopg2.connect(DB_URL)


def search_similar_chunks(conn, query_embedding, domain=None, limit=8):
    """
    Perform vector similarity search, optionally filtered by domain.

    This is hybrid search: vector similarity (semantic) + metadata filter (structured).
    The <=> operator computes cosine distance using the C-SPANN index.
    """
    sql_parts = [
        "SELECT s.skill_name, s.title, s.domain, s.bloom_level,",
        "       c.section_title, c.content,",
        "       c.embedding <=> %s::VECTOR(384) AS distance",
        "FROM chunks c",
        "JOIN skills s ON s.id = c.skill_id",
    ]

    params = [vector_to_sql_param(query_embedding)]

    if domain:
        sql_parts.append("WHERE s.domain = %s")
        params.append(domain)

    sql_parts.append("ORDER BY distance ASC")
    sql_parts.append(f"LIMIT {limit}")

    sql = "\n".join(sql_parts)

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def vector_to_sql_param(vec):
    """Format embedding as a string parameter for SQL."""
    return "[" + ",".join(f"{v:.6f}" for v in vec) + "]"


def get_prerequisite_chain(conn, skill_name, max_depth=5):
    """
    Follow prerequisite edges recursively to build a learning path.

    Uses a recursive CTE to traverse the prerequisites graph,
    returning skills ordered from foundational to advanced.
    """
    sql = """
    WITH RECURSIVE chain AS (
        SELECT prerequisite_name, 1 AS depth
        FROM prerequisites
        WHERE skill_name = %s
        UNION ALL
        SELECT p.prerequisite_name, c.depth + 1
        FROM prerequisites p
        JOIN chain c ON p.skill_name = c.prerequisite_name
        WHERE c.depth < %s
    )
    SELECT DISTINCT prerequisite_name, MIN(depth) as depth
    FROM chain
    GROUP BY prerequisite_name
    ORDER BY depth DESC
    """

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, (skill_name, max_depth))
        return cur.fetchall()


def get_skill_details(conn, skill_name):
    """Get full details for a specific skill."""
    sql = """
    SELECT skill_name, title, domain, bloom_level,
           left(full_content, 2000) as summary
    FROM skills
    WHERE skill_name = %s
    """
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, (skill_name,))
        return cur.fetchone()


def format_results(symptom, results, prereq_chains):
    """Format search results into structured troubleshooting output."""
    output = []
    output.append("=" * 70)
    output.append(f"TROUBLESHOOTING: {symptom}")
    output.append("=" * 70)
    output.append("")

    # Group results by skill
    seen_skills = {}
    for r in results:
        skill = r["skill_name"]
        if skill not in seen_skills:
            seen_skills[skill] = {
                "title": r["title"],
                "domain": r["domain"],
                "bloom_level": r["bloom_level"],
                "sections": [],
                "best_distance": r["distance"],
            }
        seen_skills[skill]["sections"].append({
            "section_title": r["section_title"],
            "content": r["content"][:500],
            "distance": r["distance"],
        })

    # Display top skills
    output.append(f"Found {len(seen_skills)} relevant skills:")
    output.append("")

    for i, (skill_name, info) in enumerate(seen_skills.items(), 1):
        relevance = max(0, (1 - info["best_distance"]) * 100)
        output.append(f"  {i}. {info['title']}")
        output.append(f"     Domain: {info['domain']} | Level: {info['bloom_level']} | Relevance: {relevance:.0f}%")

        # Show matched sections
        for section in info["sections"][:2]:
            output.append(f"     > {section['section_title']}")
            # Show first 200 chars of content
            preview = section["content"][:200].replace("\n", " ")
            output.append(f"       {preview}...")

        output.append("")

    # Show prerequisite chains
    if prereq_chains:
        output.append("-" * 70)
        output.append("PREREQUISITE LEARNING PATH:")
        output.append("")
        for skill_name, chain in prereq_chains.items():
            if chain:
                output.append(f"  Before '{skill_name}', first learn:")
                for prereq in chain:
                    depth_indicator = "  " * prereq["depth"]
                    output.append(f"    {depth_indicator}-> {prereq['prerequisite_name']}")
                output.append("")

    output.append("-" * 70)
    output.append("TIP: Use Claude Code to query the opsrag database directly for deeper analysis.")
    output.append("     Example: claude 'Query opsrag and help me troubleshoot: <your symptom>'")
    output.append("")

    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(
        description="RAG-powered CockroachDB troubleshooting assistant"
    )
    parser.add_argument(
        "symptom",
        help="Describe the problem or symptom (e.g., 'node is unresponsive')"
    )
    parser.add_argument(
        "--domain",
        help="Filter results to a specific domain (e.g., 'Cluster Maintenance', 'Backup and Restore', 'Multi-Region')",
        default=None,
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=8,
        help="Maximum number of chunks to retrieve (default: 8)",
    )
    parser.add_argument(
        "--no-prereqs",
        action="store_true",
        help="Skip prerequisite chain lookup",
    )

    args = parser.parse_args()

    print(f"\nEmbedding query: '{args.symptom}'...", file=sys.stderr)
    query_embedding = embed(args.symptom)

    print(f"Searching opsrag database...", file=sys.stderr)
    conn = connect()

    try:
        # Vector similarity search (hybrid if domain specified)
        results = search_similar_chunks(conn, query_embedding, domain=args.domain, limit=args.limit)

        if not results:
            print("No results found. Try a different query or remove the --domain filter.")
            sys.exit(1)

        # Get prerequisite chains for top skills
        prereq_chains = {}
        if not args.no_prereqs:
            seen = set()
            for r in results:
                skill = r["skill_name"]
                if skill not in seen:
                    seen.add(skill)
                    chain = get_prerequisite_chain(conn, skill)
                    if chain:
                        prereq_chains[skill] = chain

        # Format and display
        output = format_results(args.symptom, results, prereq_chains)
        print(output)

    finally:
        conn.close()


if __name__ == "__main__":
    main()
