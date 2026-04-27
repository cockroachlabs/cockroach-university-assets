#!/usr/bin/env python3
"""
Parse a SKILL.md file, chunk by section, embed, and insert into CockroachDB.

This script demonstrates the complete ingestion pipeline:
1. Parse YAML frontmatter and markdown sections
2. Generate 384-dim embeddings for each section
3. Insert skill metadata, chunks with vectors, and prerequisite edges

Usage:
    python3 add_skill.py /root/lab/data/new_skill.md
"""

import sys
import re
import uuid
import yaml
import psycopg2
from embeddings import embed


DB_URL = "postgresql://root@localhost:26257/opsrag?sslmode=require&sslrootcert=/root/certs/ca.crt&sslcert=/root/certs/client.root.crt&sslkey=/root/certs/client.root.key"


def parse_skill_md(filepath):
    """
    Parse a SKILL.md file into structured data.

    Returns:
        tuple: (frontmatter_dict, list_of_(section_title, section_content))
    """
    with open(filepath, "r") as f:
        content = f.read()

    # Extract YAML frontmatter between --- markers
    fm_match = re.match(r"^---\n(.*?)\n---\n(.*)", content, re.DOTALL)
    if not fm_match:
        print(f"WARNING: No YAML frontmatter found. Using defaults.")
        frontmatter = {"name": "unnamed-skill", "metadata": {}}
        body = content
    else:
        frontmatter = yaml.safe_load(fm_match.group(1))
        body = fm_match.group(2)

    # Split body into sections by ## headings
    sections = []
    current_title = "Introduction"
    current_lines = []

    for line in body.split("\n"):
        heading_match = re.match(r"^##\s+(.+)$", line)
        if heading_match:
            section_text = "\n".join(current_lines).strip()
            if section_text and len(section_text) >= 50:
                sections.append((current_title, section_text))
            current_title = heading_match.group(1).strip()
            current_lines = []
        else:
            current_lines.append(line)

    # Save last section
    section_text = "\n".join(current_lines).strip()
    if section_text and len(section_text) >= 50:
        sections.append((current_title, section_text))

    return frontmatter, sections, content


def insert_skill(conn, frontmatter, sections, full_content):
    """
    Insert a skill and its chunks into the opsrag database.

    Steps:
    1. Insert skill metadata into skills table
    2. For each section: generate embedding, insert into chunks table
    3. Insert prerequisite edges if defined in frontmatter
    """
    meta = frontmatter.get("metadata", {})
    skill_name = frontmatter.get("name", "unnamed-skill")
    title = frontmatter.get("description", skill_name.replace("-", " ").title())
    domain = meta.get("domain", "General")
    bloom_level = meta.get("bloom_level", "Apply")

    # Generate a deterministic UUID from skill name
    skill_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"skill:{skill_name}"))

    cur = conn.cursor()

    try:
        # Step 1: Insert skill metadata
        print(f"  Inserting skill: {skill_name}")
        cur.execute(
            """INSERT INTO skills (id, skill_name, title, domain, bloom_level, full_content)
               VALUES (%s, %s, %s, %s, %s, %s)
               ON CONFLICT (skill_name) DO UPDATE SET
                   title = EXCLUDED.title,
                   domain = EXCLUDED.domain,
                   bloom_level = EXCLUDED.bloom_level,
                   full_content = EXCLUDED.full_content""",
            (skill_id, skill_name, title, domain, bloom_level, full_content[:8000])
        )

        # Delete existing chunks for this skill (for upsert behavior)
        cur.execute("DELETE FROM chunks WHERE skill_id = %s", (skill_id,))

        # Step 2: Chunk and embed each section
        print(f"  Generating embeddings for {len(sections)} sections...")
        for idx, (section_title, section_content) in enumerate(sections):
            # Create embedding from section title + content
            embed_text = f"{title}: {section_title}\n{section_content[:1500]}"
            embedding = embed(embed_text)

            # Format as vector literal
            vec_literal = "[" + ",".join(f"{v:.6f}" for v in embedding) + "]"

            chunk_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"chunk:{skill_name}:{idx}"))

            cur.execute(
                """INSERT INTO chunks (id, skill_id, section_title, content, chunk_index, embedding)
                   VALUES (%s, %s, %s, %s, %s, %s::VECTOR(384))""",
                (chunk_id, skill_id, section_title, section_content[:4000], idx, vec_literal)
            )
            print(f"    [{idx}] {section_title} ({len(section_content)} chars)")

        # Step 3: Insert prerequisite edges
        related_skills = meta.get("related_skills", [])
        if related_skills:
            print(f"  Adding {len(related_skills)} prerequisite edges...")
            for prereq in related_skills:
                cur.execute(
                    """INSERT INTO prerequisites (skill_name, prerequisite_name)
                       VALUES (%s, %s)
                       ON CONFLICT DO NOTHING""",
                    (skill_name, prereq)
                )

        conn.commit()
        print(f"\n  Done! Skill '{skill_name}' added with {len(sections)} chunks.")

    except Exception as e:
        conn.rollback()
        raise e
    finally:
        cur.close()


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 add_skill.py <path-to-SKILL.md>")
        print("")
        print("Example:")
        print("  python3 add_skill.py /root/lab/data/new_skill.md")
        sys.exit(1)

    filepath = sys.argv[1]

    try:
        with open(filepath, "r") as f:
            pass
    except FileNotFoundError:
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    print(f"\n{'='*60}")
    print(f"Adding skill from: {filepath}")
    print(f"{'='*60}\n")

    # Parse the SKILL.md file
    print("Step 1: Parsing SKILL.md...")
    frontmatter, sections, full_content = parse_skill_md(filepath)
    print(f"  Found {len(sections)} sections")

    # Connect to database
    print("\nStep 2: Connecting to CockroachDB...")
    conn = psycopg2.connect(DB_URL)
    print("  Connected to opsrag database")

    try:
        # Insert skill and chunks
        print("\nStep 3: Inserting skill, chunks, and embeddings...")
        insert_skill(conn, frontmatter, sections, full_content)

        # Verify
        print("\nStep 4: Verifying insertion...")
        cur = conn.cursor()
        cur.execute(
            "SELECT count(*) FROM chunks WHERE skill_id = (SELECT id FROM skills WHERE skill_name = %s)",
            (frontmatter.get("name", "unnamed-skill"),)
        )
        count = cur.fetchone()[0]
        cur.close()
        print(f"  Verified: {count} chunks in database")

        print(f"\n{'='*60}")
        print(f"SUCCESS: Skill is now searchable via troubleshoot.py")
        print(f"{'='*60}\n")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
