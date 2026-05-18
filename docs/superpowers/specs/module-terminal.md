# Module Spec: terminal.lua

## Overview

Terminal state management and text insertion. Manages terminal lifecycle, ready detection, and text transmission.

## Key Data Structures

### `M.terminals`

Table mapping `integration.name` → terminal data:

```lua
{
  cli_term = TerminalWindow,  -- Terminal object from window.lua
  term_buf = number,           -- Terminal buffer handle
  working_dir = string,        -- Current working directory
  current_file = string,       -- Relative file path
  is_expanded = boolean,       -- Fullwidth state
  integration = Integration,    -- Integration configuration
}
```

### `M.buf_to_name`

Reverse index for fast lookup: `term_buf → integration.name`

## Public API

### `M.open_terminal(integration, args, keep_open, working_dir, visual_text)`

Creates or toggles terminal.

**Toggle behavior:**

- If terminal exists and buffer is valid → toggle visibility
- If terminal buffer is invalid → clean up and create new

**Creation flow (`create_new_terminal`):**

1. Resolve working directory and current file path
2. Run `on_open` hook if configured
3. Call `window.create_terminal()` with configuration
4. Store terminal data in `M.terminals[name]`
5. Update `M.buf_to_name[term_buf]`
6. If `visual_text` or `start_with_text` is set → attach text when ready
7. Handle `open_delay` if configured

### `M.insert_text(text, term_buf)`

Sends text to terminal via `chansend`. Checks job is alive via `jobwait`.

### `M.attach_text_when_ready(integration, term_buf, tries, visual_text)`

Polls terminal output for ready flag.

**Ready detection:**

- Searches range defined by `cli_ready_flags` for `search_for` or `cli_cmd`
- Max 30 tries, 500ms intervals
- When found: evaluates `start_with_text` (string or function) and inserts

### `M.toggle_width(term_buf)`

Toggles between default and fullwidth. Delegates to `window.update_sidebar_geometry()`.

### `M.hide_terminal(term_buf)`

Hides window, keeps process alive.

### `M.close_terminal(term_buf)`

Closes window and kills process. Cleans up state tables.

### `M.get_current_terminal_buf()`

Returns current buffer if it's a terminal.

### `M.get_integration_for_buf(term_buf)`

Returns integration config for buffer via `buf_to_name` lookup.

### `M.find_terminal_window(term_buf)`

Finds window displaying terminal buffer.

### `M.get_terminal_job_id(term_buf)`

Gets job_id for terminal buffer (handles both old and new Neovim APIs).

### `M.focus_terminal_window(term_buf)`

Focuses window containing terminal buffer and enters insert mode.

## Critical Details

- `start_with_text`: Can be string or function(visual_text, integration) → string
- Visual text priority: `visual_text` overrides `start_with_text` string
- Toggle behavior: If terminal exists and valid, toggles visibility; otherwise creates new
- Cleanup: `on_close` callback removes from `M.terminals` and `M.buf_to_name`
- Ready detection polls every 500ms, max 30 tries (15 seconds timeout)

## Source Location

`lua/cli-integration/terminal.lua` (532 lines)
