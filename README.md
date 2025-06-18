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


## Using *IInstruqt*

- `code-server`. By default the Code Server will be using port `3001`, so ensure you use the port `3000` as part of the `Tab Port`.
- `cockroachdb-ui`. By default, the CockroachDB UI uses `8080`, but you need to use the port `3080` in the `Tab port`.


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

## Example of Execution with Parameters to the Scripts

```bash
#!/bin/bash

# Define SCRIPTS as an array of strings, where each string can include parameters.
# For scripts with parameters, enclose the entire command in double quotes.
# For scripts without parameters, simply list the path.
SCRIPTS=(
    "codeserver/codeserver-ext-jvm.sh"
    "courses/cdc/01-fundamentals.sh param1 param2" # Example with parameters
    "another/script/path.sh -f --verbose"         # Another example
    "yet/another/script.sh"                       # Script without parameters
)

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/"

for SCRIPT_CMD_FULL in "${SCRIPTS[@]}"; do
    echo "[INFO] **************************************************"

    # Extract the script path (the first "word" in the command string)
    SCRIPT_PATH=$(echo "$SCRIPT_CMD_FULL" | awk '{print $1}')

    # Extract just the filename
    SCRIPT_NAME=$(basename "$SCRIPT_PATH")
    TMP_PATH="/tmp/$SCRIPT_NAME"

    # Extract the parameters (all "words" after the first one)
    # This creates an array of parameters
    SCRIPT_PARAMS=()
    if [[ $(echo "$SCRIPT_CMD_FULL" | wc -w) -gt 1 ]]; then
        # Use read -ra to parse the remaining arguments into an array
        read -ra SCRIPT_PARAMS <<< "$(echo "$SCRIPT_CMD_FULL" | cut -d' ' -f2-)"
    fi

    # Download using the full relative path from GitHub
    echo "[INFO] Attempting to download: ${BASE_URL}${SCRIPT_PATH}"
    curl -fsSL "${BASE_URL}${SCRIPT_PATH}" -o "$TMP_PATH"

    if [[ $? -eq 0 ]]; then
        echo "[INFO] Successfully downloaded $SCRIPT_NAME to $TMP_PATH"
        chmod +x "$TMP_PATH"
        echo "[INFO] Executing $SCRIPT_NAME with parameters: ${SCRIPT_PARAMS[*]}"
        # Execute the script with its extracted parameters
        "$TMP_PATH" "${SCRIPT_PARAMS[@]}"
        EXEC_STATUS=$? # Capture the exit status of the executed script

        if [[ $EXEC_STATUS -eq 0 ]]; then
            echo "[INFO] Script $SCRIPT_NAME executed successfully."
        else
            echo "❌ Script $SCRIPT_NAME exited with error status: $EXEC_STATUS"
        fi

        rm -f "$TMP_PATH"
    else
        echo "❌ Failed to download $SCRIPT_PATH"
    fi
done
```