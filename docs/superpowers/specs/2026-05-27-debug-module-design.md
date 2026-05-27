# Spec: Debug Module for cli-integration.nvim

**Date:** 2026-05-27
**Status:** Approved
**Context:** Neovim + cli-integration.nvim plugin

---

## 1. Problem Statement

The `cli-integration.nvim` plugin manages terminal windows, buffers, and complex window lifecycle transitions (sidebar ↔ fullscreen). Debugging issues like visual artifacts, buffer leaks, window state corruption, and keymap timing problems requires printf-style logging scattered across multiple modules. Currently there is no structured way to trace what the plugin is doing, which makes diagnosing problems extremely difficult.

## 2. Design Overview

### 2.1 Approach: Centralized `debug.log()` with lazy evaluation

A single new module `debug.lua` exposes `M.log(event, data_fn)`. All modules call this function at strategic points. When `config.options.debug` is `false` (the default), `debug.log()` returns immediately—no string construction, no file I/O, no function evaluation.

When `debug = true`, the `data_fn` function is evaluated, its result is formatted, and appended to a log file in the current working directory.

### 2.2 Why this approach

- **Zero overhead when disabled**: Single `if not config.options.debug then return end` check per call.
- **Centralized format**: All log lines go through one function, ensuring consistent format.
- **Lazy evaluation**: Data is only constructed when debug is enabled, passed as a function `data_fn`.
- **No persistent state**: No file handles held open, no timers, no autocmds for cleanup.

## 3. Configuration

### 3.1 New field in `Cli-Integration.Config`

```lua
--- @class Cli-Integration.Config
--- @field ... existing fields ...
--- @field debug boolean|nil # Enable debug logging (default: false)
```

### 3.2 Default value

```lua
M.defaults = {
    -- ... existing defaults ...
    debug = false,
}
```

### 3.3 Usage

```lua
require("cli-integration").setup({
    debug = true,
    integrations = { ... }
})
```

## 4. Module: `debug.lua`

### 4.1 Public API

```lua
--- @param event string Event name (e.g., "toggle_fullscreen", "hide", "create_terminal")
--- @param data_fn fun():table Lazy function returning data to log
debug.log(event, data_fn)
```

### 4.2 Behavior

1. Early return: `if not config.options.debug then return end`
2. Evaluate `data_fn()` to get the data table
3. Format entry: `[YYYY-MM-DD HH:MM:SS] [cli-integration] <event> | key=value key=value ...`
4. Append to log file: `vim.fn.getcwd() .. "/cli-integration-debug.log"`
5. Flush on each write (file opened in append mode, written, closed)

### 4.3 Private helpers

- `format_entry(event, data)` → converts table to `key=value` pairs separated by spaces
- `get_timestamp()` → returns formatted timestamp string

### 4.4 Log file location

`<cwd>/cli-integration-debug.log` where `<cwd>` is `vim.fn.getcwd()` at the time of the log call. This means the log file appears in the Neovim working directory.

## 5. Instrumentation Points

### 5.1 `terminal.lua`

| Event               | Data fields                        | Trigger                            |
| ------------------- | ---------------------------------- | ---------------------------------- |
| `open_terminal`     | name, cli_cmd, working_dir         | New terminal created               |
| `toggle_terminal`   | name, term_buf                     | Existing terminal toggled          |
| `hide_terminal`     | name, term_buf, term_win           | Terminal window hidden             |
| `close_terminal`    | name, term_buf, job_id             | Terminal closed and process killed |
| `toggle_fullscreen` | name, term_buf, from_mode, to_mode | Fullscreen mode toggled            |
| `focus_terminal`    | name, term_buf, term_win           | Terminal window focused            |
| `insert_text`       | name, text_length                  | Text inserted into terminal        |
| `attach_text_ready` | name, term_buf, tries              | CLI ready detected, text attached  |

### 5.2 `window.lua`

| Event                     | Data fields                                          | Trigger                            |
| ------------------------- | ---------------------------------------------------- | ---------------------------------- |
| `create_terminal`         | cmd, buf, job_id, width, height                      | Terminal buffer+job created        |
| `create_float_window`     | buf, win, width, height                              | Float window created               |
| `create_sidebar_layout`   | buf, sidebar_win, width                              | Sidebar vsplit created             |
| `update_sidebar_geometry` | term_buf, from_mode, to_mode, sidebar_win, float_win | Sidebar/fullscreen geometry change |
| `update_float_geometry`   | term_buf, from_mode, to_mode, float_win              | Float geometry change              |
| `resize_sidebars`         | resized_bufs, editor_width                           | Editor resize triggered            |
| `create_proxy_split`      | proxy_buf, proxy_win                                 | Navigation proxy split created     |

### 5.3 `keymaps.lua`

| Event                       | Data fields      | Trigger                  |
| --------------------------- | ---------------- | ------------------------ |
| `keymap_hide`               | name, buf, mode  | Hide keymap executed     |
| `keymap_close`              | name, buf, mode  | Close keymap executed    |
| `keymap_toggle_fullscreen`  | name, buf, mode  | Fullscreen toggle keymap |
| `keymap_insert_file_path`   | name, buf, path  | File path insertion      |
| `keymap_insert_all_buffers` | name, buf, count | All buffers insertion    |
| `keymap_submit`             | name, buf, mode  | Submit keymap            |
| `keymap_help`               | name, buf        | Help keymap              |

### 5.4 `ask.lua`

| Event        | Data fields                                      | Trigger            |
| ------------ | ------------------------------------------------ | ------------------ |
| `ask_open`   | integration_name                                 | Ask flow started   |
| `ask_submit` | integration_name, question_length, has_selection | Question submitted |
| `ask_cancel` | integration_name                                 | Ask cancelled      |

### 5.5 `hooks.lua` / `commands.lua` / `autocmds.lua`

| Event                | Data fields       | Trigger                   |
| -------------------- | ----------------- | ------------------------- |
| `hook_on_open`       | name, working_dir | on_open hook called       |
| `hook_on_close`      | name, working_dir | on_close hook called      |
| `command_open_cwd`   | name, working_dir | :CLIIntegration open_cwd  |
| `command_open_root`  | name, working_dir | :CLIIntegration open_root |
| `autocmd_term_open`  | name, buf         | TermOpen autocmd          |
| `autocmd_term_enter` | name, buf         | TermEnter autocmd         |

### 5.6 `init.lua`

| Event   | Data fields                       | Trigger               |
| ------- | --------------------------------- | --------------------- |
| `setup` | integrations_count, debug_enabled | Plugin setup() called |

## 6. Zero-Overhead Guarantee

### 6.1 Early return

`debug.log()` checks `config.options.debug` first. If `false`, returns immediately. No strings are built, no functions are called, no I/O occurs.

### 6.2 Lazy evaluation pattern

All call sites use the lazy pattern:

```lua
-- Correct: table built only when debug is active
debug.log("toggle_fullscreen", function()
    return { name = name, buf = term_buf, mode = data.mode }
end)

-- Wrong: table built unconditionally
local info = { name = name, buf = term_buf, mode = data.mode }
debug.log("toggle_fullscreen", function() return info end)
```

### 6.3 No persistent file handle

The log file is opened in append mode on each write and closed immediately. No file handle is held open, no timers or autocmds are needed for cleanup.

### 6.4 Cached require

`debug.lua` is loaded via `require()` once per module. Lua caches requires, so subsequent calls are a table lookup. No conditional loading or lazy require needed.

## 7. Log Format Example

```
[2026-05-27 14:32:01] [cli-integration] setup | integrations_count=3 debug_enabled=true
[2026-05-27 14:32:05] [cli-integration] command_open_cwd | name=open_cwd working_dir=/home/user/project
[2026-05-27 14:32:05] [cli-integration] create_terminal | cmd=opencode buf=5 job_id=12 width=80 height=24
[2026-05-27 14:32:05] [cli-integration] create_sidebar_layout | buf=5 sidebar_win=1001 width=34
[2026-05-27 14:32:10] [cli-integration] keymap_toggle_fullscreen | name=opencode buf=5 mode=T
[2026-05-27 14:32:10] [cli-integration] toggle_fullscreen | name=opencode buf=5 from_mode=sidebar to_mode=fullscreen
[2026-05-27 14:32:10] [cli-integration] update_sidebar_geometry | term_buf=5 from_mode=sidebar to_mode=fullscreen sidebar_win=1001 float_win=1002
[2026-05-27 14:32:12] [cli-integration] keymap_toggle_fullscreen | name=opencode buf=5 mode=n
[2026-05-27 14:32:12] [cli-integration] toggle_fullscreen | name=opencode buf=5 from_mode=fullscreen to_mode=sidebar
[2026-05-27 14:32:12] [cli-integration] update_sidebar_geometry | term_buf=5 from_mode=fullscreen to_mode=sidebar sidebar_win=1003 float_win=nil
[2026-05-27 14:32:15] [cli-integration] keymap_hide | name=opencode buf=5 mode=T
[2026-05-27 14:32:15] [cli-integration] hide_terminal | name=opencode buf=5 term_win=1001
```
