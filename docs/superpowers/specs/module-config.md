# Module Spec: config.lua

## Overview

Configuration management and validation. Defines all type annotations, default values, and merge logic.

## Key Types

### `Cli-Integration.Config`

Global configuration object. Fields:

- `integrations: Integration[]` — Array of CLI integrations
- `show_help_on_open: boolean` — Show help on terminal open (default: true)
- `new_lines_amount: number` — Newlines after submit (default: 2)
- `window_width: number` — Width percentage (1-100) or absolute (>100) (default: 34)
- `window_padding: number` — Horizontal padding in columns (default: 0)
- `border: string` — Border style (default: "none")
- `floating: boolean` — Open in floating window (default: false)
- `terminal_keys: TerminalKeys` — Key mappings
- `start_insert_on_click: boolean` — Re-enter insert on click (default: false)
- `list_buffer: boolean` — List terminal buffer in bufferline (default: false)
- `env: table<string, string>` — Environment variable overrides
- `unset_env: string[]` — Environment variable names to remove

### `Cli-Integration.Integration`

Per-CLI-tool configuration. Inherits from Config, adds:

- `cli_cmd: string` — REQUIRED: CLI command name
- `name: string` — REQUIRED: Display name for autocompletion
- `keep_open: boolean` — Keep terminal open after execution (default: false)
- `start_with_text: string|function` — Text to insert when ready
- `cli_ready_flags: CliReadyFlags` — Readiness detection config
- `format_paths: function(paths, actions)` — Path formatting callback. Receives all paths and an actions table with `send_line`, `send_keys`, `wait`, and `for_each_path`. Does not return a value.
- `open_delay: number` — Delay before creating terminal (default: 0)
- `on_open: function` — Pre-launch hook
- `on_close: function` — Post-exit hook
- `on_ask_submit: function` — Ask hook callback
- `ask_title: string` — Custom ask input title

### `Cli-Integration.TerminalKeys`

```lua
{
  terminal_mode = {
    normal_mode = {"<M-q>"},
    insert_file_path = {"<C-p>"},
    insert_all_buffers = {"<C-p><C-p>"},
    new_lines = {"<S-CR>"},
    submit = {"<C-s>", "<C-CR>"},
    enter = {"<CR>"},
    help = {"<M-?>", "??", "\\"},
    toggle_width = {"<C-f>"},
    hide = {"<C-q>"},
    close = {"<C-S-q>"}
  },
  normal_mode = {
    toggle_width = {"<C-f>"},
    hide = {"<C-q>"},
    close = {"<C-S-q>"}
  }
}
```

## Default Configuration

```lua
M.defaults = {
  integrations = {},
  show_help_on_open = true,
  new_lines_amount = 2,
  window_width = 34,
  window_padding = 0,
  border = "none",
  floating = false,
  start_insert_on_click = false,
  list_buffer = false,
  env = {},
  unset_env = {},
  terminal_keys = { ... },
  on_ask_submit = function(data, actions) ... end,
}
```

## Merge Logic

### Global Level

`M.options = vim.tbl_deep_extend("force", M.defaults, user_config)`

### Per-Integration Level

1. Validate integration has `name` and `cli_cmd` (non-empty strings)
2. Validate `terminal_keys` if provided (all values must be arrays)
3. Validate `env` if provided (string keys and values)
4. Validate `unset_env` if provided (array of strings)
5. Build merged `terminal_keys`:
   - Per-section override: if integration defines `terminal_mode` or `normal_mode`, merge key-by-key within that section
   - Undefined sections inherit from global defaults
6. Apply integration-specific config via `vim.tbl_deep_extend("force", default_integration, integration)`

## Validation Functions

- `validate_terminal_keys(terminal_keys)` — Recursively checks all values are arrays
- `validate_env(env)` — Checks table has string keys and string values
- `validate_unset_env(unset_env)` — Checks array of strings

## Critical Details

- All `terminal_keys` values MUST be arrays (enforced by validation)
- Minimum `cli_cmd` length: 2 characters (to avoid false pattern matches)
- Integration-specific config overrides global defaults
- Environment strategy: inherit full Neovim process environment by default (including NVIM/TERM/TMUX), with optional per-integration `env` overrides and `unset_env` removals
- Default `border`: "none" for sidebar, "rounded" for float/expanded

## Source Location

`lua/cli-integration/config.lua` (385 lines)
