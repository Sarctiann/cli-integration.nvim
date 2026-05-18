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

Returns a `start_with_text` function that:

- Wraps visual selection in prefix/suffix
- Returns formatted current file path if no selection

**Parameters:**

- `prefix` — Default: "Explain this code:\n```\n"
- `suffix` — Default: "\n```\n"

**Returns:** Function compatible with `start_with_text` signature

**Behavior:**

1. If `visual_text` provided → returns `prefix .. visual_text .. suffix`
2. If no visual text → looks up terminal data for integration name
3. Falls back to current buffer path relative to workspace
4. Applies `integration.format_paths` if available

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

`lua/cli-integration/hooks.lua` (180 lines)
