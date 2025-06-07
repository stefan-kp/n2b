# N2B Command Restructuring: Migration Guide (v1.x to v2.x)

## Overview

This guide outlines the key changes in command structure from N2B version 1.x to version 2.x and how to adapt your usage. The primary motivation for this restructuring is to create a clearer separation of concerns:

*   `n2b`: Now dedicated solely to natural language to shell command translation and execution.
*   `n2b-diff`: A new, comprehensive tool focused on AI-powered merge conflict resolution and code diff analysis, incorporating features previously found in `n2b --diff`.

## Key Changes & Command Mapping

Most functionalities related to diff analysis and version control integration have been moved from `n2b` to the new `n2b-diff` command, specifically under its `--analyze` mode.

Here's a summary of how old commands map to new ones:

1.  **Basic Diff Analysis:**
    *   Old: `n2b --diff`
    *   New: `n2b-diff --analyze`

2.  **Diff Analysis with Branch Specification:**
    *   Old: `n2b --diff --branch <branch_name>`
    *   New: `n2b-diff --analyze --branch <branch_name>`
    *   Example:
        *   Old: `n2b --diff --branch main`
        *   New: `n2b-diff --analyze --branch main`

3.  **Diff Analysis with Jira Integration:**
    *   Old: `n2b --diff -j <JIRA_TICKET_ID_OR_URL> [other_options]`
    *   New: `n2b-diff --analyze --jira <JIRA_TICKET_ID_OR_URL> [other_options]`
    *   The user prompt addition from the old `n2b --diff ... "custom prompt"` is now handled by the `-m/--message` option in `n2b-diff`.
    *   Old update flags `--jira-update` and `--jira-no-update` map to `--update` and `--no-update` respectively when a Jira ticket is specified.

4.  **Diff Analysis with Requirements File:**
    *   Old: `n2b --diff -r <FILE_PATH> [other_options]`
    *   New: `n2b-diff --analyze --requirements <FILE_PATH> [other_options]`

5.  **New Custom Messaging for Analysis:**
    *   `n2b-diff --analyze` introduces a dedicated option for providing custom instructions or focus points for the AI analysis:
        *   `-m, --message, --msg <MESSAGE_TEXT>`

## Examples: Side-by-Side

### General Diff Analysis

**Old (v1.x):**
```bash
n2b --diff
n2b --diff --branch feature-xyz
```

**New (v2.x):**
```bash
n2b-diff --analyze
n2b-diff --analyze --branch feature-xyz
```

### Diff Analysis with Jira & Custom Instructions

**Old (v1.x):**
```bash
# User prompt was typically the last part of the command for diff
n2b --diff -j MYPROJ-123 --jira-update "Focus on performance and check for potential race conditions."
```

**New (v2.x):**
```bash
n2b-diff --analyze --jira MYPROJ-123 --update -m "Focus on performance and check for potential race conditions."
```
*(Note: The new `--github` option in `n2b-diff --analyze` works similarly for GitHub Issues.)*

### Diff Analysis with Requirements File

**Old (v1.x):**
```bash
n2b --diff -r ./project_requirements.txt
```

**New (v2.x):**
```bash
n2b-diff --analyze --requirements ./project_requirements.txt
```

## Summary of `n2b` (v2.x)

The `n2b` command is now streamlined for direct natural language to shell command translation:

*   `n2b "your natural language query"`: Translates the query to a shell command.
*   `n2b -x "your query"`: Translates and offers to execute the command.
*   `n2b -c` / `n2b --config`: Opens configuration settings.
*   `n2b --advanced-config`: Opens advanced configuration settings.

Please update your scripts and aliases accordingly. The `n2b-diff` tool offers a more powerful and dedicated interface for all code analysis tasks.
