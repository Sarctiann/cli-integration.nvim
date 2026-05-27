# Module Spec: keymaps.lua

## Overview

Terminal keymap setup and buffer/file path insertion.

## Public API

### `M.setup_terminal_keymaps(known_integration)`

Sets up all keymaps for current terminal buffer. Called by autocmd on TermOpen/TermEnter.

**Parameters:**

- `known_integration` — Integration passed directly from autocmd (avoids timing issues with TermOpen when `buf_to_name` may not be populated)

**Fallback:** If no integration passed, looks up via `terminal.get_integration_for_buf()`

## Keymap Categories

### Terminal Mode

| Action               | Default Keys        | Behavior                                                    |
| -------------------- | ------------------- | ----------------------------------------------------------- |
| `normal_mode`        | `<M-q>`             | Enter normal mode (`<C-\><C-n>`)                            |
| `insert_file_path`   | `<C-p>`             | Insert current file path (uses `format_paths` if available) |
| `insert_all_buffers` | `<C-p><C-p>`        | Insert all open buffer paths                                |
| `new_lines`          | `<S-CR>`            | Insert `new_lines_amount` newlines (default: 2)             |
| `submit`             | `<C-s>`, `<C-CR>`   | Submit command (sends Enter)                                |
| `enter`              | `<CR>`              | Send Enter key                                              |
| `help`               | `<M-?>`, `??`, `\\` | Show help                                                   |
| `toggle_fullscreen`  | `<C-f>`             | Toggle fullscreen                                           |
| `hide`               | `<C-q>`             | Hide window (keep process)                                  |
| `close`              | `<C-S-q>`           | Close window (kill process)                                 |

### Normal Mode

| Action              | Default Keys | Behavior          |
| ------------------- | ------------ | ----------------- |
| `toggle_fullscreen` | `<C-f>`      | Toggle fullscreen |
| `hide`              | `<C-q>`      | Hide window       |
| `close`             | `<C-S-q>`    | Close window      |

### Special Mappings (always applied)

- `<CR>` in terminal mode → empty string (prevents default behavior)
- `<M-h/j/k/l>` in terminal mode → arrow keys

## Implementation Details

- Keymaps are buffer-local (`buffer=0`)
- Gets integration-specific keys or falls back to global `config.options.terminal_keys`
- File path insertion uses `integration.format_paths(paths, actions)` if available, otherwise raw path
- The `actions` table provides:
  - `send_line(text)` — send text followed by newline
  - `send_keys(keys)` — send Vim key sequences through `chansend`
  - `wait(ms)` — suspend the callback temporarily
  - `for_each_path(fn)` — iterate paths, call `fn(path)`, and insert any returned string
- `run_format_paths(paths, current_buf, integration)` wraps the callback in a coroutine so `wait()` works
- All buffers insertion gets paths via `buffers.get_open_buffers_paths(working_dir)`
- Toggle fullscreen is mapped in modes: `i`, `t`, `n`, `v`

## Source Location

`lua/cli-integration/keymaps.lua` (267 lines)
