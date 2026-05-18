# Module Spec: ask.lua

## Overview

Ask hook — captures context, opens terminal, shows floating input, sends to terminal via actions.

## Public API

### `M.ask(integration_identifier)`

Main entry point. Sequential flow:

```
1. Capture context (file, cursor, visual selection, screen position)
2. Open integration terminal (steals focus, enters normal mode)
3. Return focus to file window
4. Restore visual selection if any
5. Show floating input with 50ms delay
```

## Helper Functions

### `capture_context(screen_capture)`

Captures editing context BEFORE any window changes.

**Returns:** `AskData` table:

- `file` — Absolute path
- `relative_file` — Path relative to current directory
- `start_line` — 1-indexed start line
- `end_line` — 1-indexed end line
- `selection` — Selected text (nil if no visual selection)
- `filetype` — vim.bo.filetype

**Visual mode detection:** Checks mode for `[vV\22]` (visual, line-visual, block-visual).

### `show_input(title, screen_row, screen_col, on_submit, on_cancel)`

Creates two-window floating input:

**Outer window:**

- Border, title, and "\u276f " icon
- Non-focusable, non-editable
- `zindex = 50`

**Inner window:**

- Actual text input
- Positioned after icon via `relative = "win"`
- `zindex = 51`

**Keymaps:**

- `<CR>` — Submit (trim text, close, invoke callback)
- `<Esc>` — Cancel (close, invoke cancel callback)

### `lookup_integration(identifier)`

Resolves integration by name, index, or cli_cmd. Same logic as commands.lua.

### `open_integration(integration)`

Opens or toggles terminal, suppresses `start_with_text` so ask's question takes priority.

### `_handle_submit(integration, context, question)`

Builds actions table and calls `on_ask_submit`.

**Actions table:**

- `send(keys)` — Sends text to terminal via chansend
- `submit()` — Sends Enter with 50ms delay
- `newline()` — Sends newline character
- `focus_file()` — Moves focus to file window (does NOT stop execution)

**Auto-focus:** After `on_ask_submit` returns, terminal window is auto-focused UNLESS `focus_file()` was called.

## Critical Details

- **Sequential Flow:** Context captured first, then terminal opened (steals focus), then focus returns to file, visual selection restored, then input shown
- **50ms Delay:** Ensures terminal's scheduled stopinsert (from WinLeave) completes before entering insert mode in input
- **Title:** "Ask {name}" by default, overridable via `ask_title` config
- **Two-Window Architecture:** No prefix management needed — Backspace works naturally

## Source Location

`lua/cli-integration/ask.lua` (314 lines)
