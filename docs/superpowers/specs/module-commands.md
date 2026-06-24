# Module Spec: commands.lua

## Overview

Command execution (open_cwd, open_git_root).

## Public API

### `M.open_cwd(integration_identifier, args, visual_text)`

Opens terminal in current file's directory.

**Parameters:**

- `integration_identifier` — Index (1-based), name, or cli_cmd (defaults to first integration)
- `args` — CLI arguments string
- `visual_text` — Optional text from visual selection

**Flow:**

1. Resolve integration via `get_integration()`
2. Get working directory from current file's directory (`%:p:h`)
3. Call `terminal.open_terminal()` with `integration.keep_open`

### `M.dbg_print()`

Prints editor dimensions, sidebar state, and terminal job info for diagnosing
resize and layout issues.  Takes no arguments.

See `docs/superpowers/specs/module-dbg-print.md` for full output reference.

### `M.open_git_root(integration_identifier, args, visual_text)`

Opens terminal in project root (git root).

**Parameters:**

- Same as `open_cwd`

**Flow:**

1. Resolve integration via `get_integration()`
2. Search for `.git` directory using `vim.fs.find()`
3. If found: use git root directory
4. If not found: use current directory and notify user
5. Call `terminal.open_terminal()` with `integration.keep_open`

## Helper Functions

### `get_integration(identifier)`

Resolves integration by:

1. Name (normalized with underscores→spaces)
2. Name (original)
3. cli_cmd (backward compatibility)

**Returns:** Integration config or nil + error message

## Source Location

`lua/cli-integration/commands.lua` (~170 lines)
