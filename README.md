# Cockroach University Assets

This repository contains assets for all the courses offered in Cockroach Labs.

Structure:

| Folder Name | Description |
|-------------|-------------|
| base        | base ubuntu scripts/assets, this will help in setting up the environment |
| codeserver  | scripts/assets for setting up a code server environment |
| courses     | All the scripts/assets per course |


## Scripts

- **`base/01-ubuntu.sh`**: This script sets up the base Ubuntu environment.
- **`base/ubuntu-jvm-21.sh`**: This script installs the Java Virtual Machine 21.
- **`base/cockroachdb.sh`**: This script installs CockroachDB on the base environment.
- **`codeserver/01-codeserver.sh`**: This script sets up the code server environment.
- **`codeserver/codeserver-ext-jvm.sh`**: This script adds JVM extensions to the code server.
- **`courses/migration/01-ubuntu-dbs.sh`**: This script if for the `migration` course.

## Rules

**Script Naming Convention**

- `[#-]<name>.sh`:
   - You can add a number at the beginning of the script; this will indicate the order that it should be executed. If no number, means it can be executed at any time _after_ any numbered script.
   - If you need to run the script at the end, you can add a bigger number.
- `[#-]<name>[-<ext>[-<ext>]].sh`:
   - You can use this format to include additional extensions if needed, allowing for more complex script naming.
   - Ensure that the main script name remains clear and descriptive.
   - If you have multiple extensions or features, separate them with a `-` (e.g., `ubuntu-feature1-feature2.sh`).  
   - Always test your scripts to ensure they function as expected.


## Example of Excution

```bash
#!/bin/bash

SCRIPTS=(
  "base/01-ubuntu.sh"
  "base/ubuntu-jvm-21.sh"
  "base/cockroachdb.sh"
  "codeserver/01-codeserver.sh"
  "codeserver/codeserver-ext-jvm.sh"
  "courses/migration/01-ubuntu-dbs.sh"
  "courses/migration/molt.sh"
)

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/"

for SCRIPT_PATH in "${SCRIPTS[@]}"; do
    SCRIPT_NAME=$(basename "$SCRIPT_PATH")      # Extract just the filename
    TMP_PATH="/tmp/$SCRIPT_NAME"                # Full temp path to save

    # Download using the full relative path from GitHub
    curl -fsSL "${BASE_URL}${SCRIPT_PATH}" -o "$TMP_PATH"

    if [[ $? -eq 0 ]]; then
        chmod +x "$TMP_PATH"
        "$TMP_PATH"
        rm -f "$TMP_PATH"
    else
        echo "❌ Failed to download $SCRIPT_PATH"
    fi
done

```