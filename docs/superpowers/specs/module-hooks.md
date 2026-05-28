# Module Spec: hooks.lua

## Overview

Shared hooks and utilities for integration workflows.

## Public API

### `M.get_current_workspace()`

Returns git root or cwd for workspace detection.

**Implementation:**

- Runs `git rev-parse --show-toplevel`
- Falls back to `vim.fn.getcwd()` if git command fails

### `M.insert_current_path_or_explain_selection(prefix, suffix)`

Returns a `start_doing` function that:

- Wraps visual selection in prefix/suffix via `actions.send_line()`
- Sends the current file path if no selection is present (calls `integration.format_paths({path}, actions)` if available, otherwise `actions.send_line(path)`)

**Parameters:**

- `prefix` — Default: "Explain this code:\n```\n"
- `suffix` — Default: "\n```\n"

**Returns:** Function compatible with `start_doing` signature: `(visual_text, integration_name, actions)`

**Behavior:**

1. If `visual_text` provided → `actions.send_line(prefix .. visual_text .. suffix)`
2. If no visual text → gets path, calls `integration.format_paths({path}, actions)` if available, otherwise `actions.send_line(path)`

### `M.manage_sessions(opts)`

Generalized session manager engine with picker UI.

**Parameters:** `opts: Cli-Integration.ManageSessionsOpts`

**Flow:**

1. Get sessions (via `opts.get_sessions()` or scan `opts.base_dir`)
2. Filter by current workspace (unless `opts.show_all`)
3. Sort by most recent (`modified` field)
4. Show picker: "Toggle All Sessions" / "Create New Session" / session list
5. On session selection: "Resume" / "Delete" / "Go Back"

## Key Types

### `Cli-Integration.Session`

```lua
{
  id = string,           -- Session identifier
  modified = string,     -- ISO date or timestamp
  display = string,        -- Optional display text
  workspace = string,      -- Optional workspace root
  file_path = string,      -- Absolute path to session file
}
```

### `Cli-Integration.ManageSessionsOpts`

```lua
{
  name = string,                    -- CLI name (e.g., "Gemini")
  base_dir = string,                -- Session storage path
  pattern = string,                 -- Glob pattern (default: "*")
  get_sessions = function,          -- Alternative: returns Session[]
  parse_session = function,         -- Extract session from file
  resume_cmd = string,              -- Command template with %s for id
  delete_cmd = function,            -- Delete logic
  show_all = boolean,               -- Initial toggle state
}
```

## Source Location

`lua/cli-integration/hooks.lua` (82 lines)
