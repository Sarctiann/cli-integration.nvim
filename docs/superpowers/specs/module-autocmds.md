# Module Spec: autocmds.lua

## Overview

Autocommand setup for terminal lifecycle events.

## Public API

### `M.setup(user_config)`

Creates autocommands for each integration.

**Early return:** If no integrations configured.

## Augroups

- **"CLI-Integration"** — Keymaps setup
- **"CLI-Integration-Opens"** — Help display

## Terminal Identification Strategy

Uses `b:cli_integration_name` buffer variable (set before termopen) instead of pattern matching on buffer names.

**Why:** Neovim overwrites buffer names during termopen with `term://...` patterns.

**Resolution:**

1. Build `integrations_by_name` lookup table for O(1) resolution
2. On TermOpen/TermEnter: read buffer variable, look up integration
3. Pass integration directly to `keymaps.setup_terminal_keymaps()`

## Autocommands

### TermOpen + TermEnter

- Pattern: `*` (all buffers, filtered by buffer variable)
- Calls `keymaps.setup_terminal_keymaps(integration)` with error handling
- Uses `args.buf` for reliable buffer identity

### TermOpen (Help)

- Only for integrations with `show_help_on_open = true`
- Delayed by 300ms via `vim.defer_fn` to avoid interfering with early terminal output
- Calls `help.show_quick_help()` with error handling

## Source Location

`lua/cli-integration/autocmds.lua` (96 lines)
