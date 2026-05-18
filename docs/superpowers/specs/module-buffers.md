# Module Spec: buffers.lua

## Overview

Buffer path collection and filtering.

## Public API

### `M.get_open_buffers_paths(working_dir)`

Returns array of file paths for all listed buffers.

**Filters:**

- `buflisted = true` (visible in bufferline)
- `buftype = ""` (normal files only)

**Excludes patterns:**

- `//` — Protocol buffers (e.g., `term://`, `nvim-tree://`)
- `neo-tree` — neo-tree sidebar

**Path conversion:**

- Absolute → relative to `working_dir` (if valid directory)
- Falls back to current directory
- Uses `vim.fs.relpath()` with fallback to `vim.fn.fnamemodify(path, ":.")`

## Implementation Details

- Iterates all buffers via `vim.api.nvim_list_bufs()`
- Validates buffer before reading properties
- Returns empty array if no matching buffers

## Source Location

`lua/cli-integration/buffers.lua` (60 lines)
