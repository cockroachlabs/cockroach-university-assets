# Cockroach University Assets

This repository contains assets for all the courses offered in Cockroach Labs.

Structure:

| Folder Name | Description |
|-------------|-------------|
| base        | base ubuntu scripts/assets, this will help in setting up the environment |
| codeserver  | scripts/assets for setting up a code server environment |
| courses     | All the scripts/assets per course |


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
