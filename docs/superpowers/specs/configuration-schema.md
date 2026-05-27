# Configuration Schema

## Integration Configuration

```lua
{
  cli_cmd = "string",              -- REQUIRED: CLI command name
  name = "string",                 -- REQUIRED: Display name for autocompletion
  show_help_on_open = boolean,     -- Default: true
  new_lines_amount = number,       -- Default: 2
  window_width = number,           -- Default: 34 (percentage 1-100 or absolute >100)
  window_padding = number,         -- Default: 0 (horizontal padding in columns)
  border = "none"|"single"|"double"|"rounded"|"solid"|"shadow", -- Default: "none"
  floating = boolean,              -- Default: false (true = centered float, false = sidebar)
  keep_open = boolean,             -- Default: false (true = keep after exit code 0)
  start_insert_on_click = boolean, -- Default: false (re-enter insert when clicking inside terminal while in normal mode)
  list_buffer = boolean,           -- Default: false (list buffer in bufferline as "[name]"; sidebar only: shifts window 1 row down)
  env = { KEY = "value" },        -- Optional: env var overrides merged on top of inherited process env
  unset_env = { "KEY" },          -- Optional: env var names removed after merge
  start_with_text = string|function(visual_text), -- Optional: text to insert when ready
  cli_ready_flags = { search_for = string, from_line = number, lines_amt = number }, -- Optional: config for readiness (default: cli_cmd, 1, 5)
  format_paths = function(path),   -- Optional: format file paths before insertion
  open_delay = number,             -- Optional: milliseconds to wait before creating terminal (default: 0)
  on_open = function(integration, working_dir), -- Optional: called before terminal creation
  on_close = function(integration, working_dir), -- Optional: called after terminal process exits
  ask_title = string,              -- Optional: override default "Ask {name}" title for ask input window
  on_ask_submit = nil|fun(data: Cli-Integration.AskData, actions: Cli-Integration.AskActions), -- Optional: callback for ask submit
  terminal_keys = {                -- Optional: override global keys
    terminal_mode = { ... },
    normal_mode = { ... }
  }
}
```

## Terminal Keys Schema

```lua
terminal_keys = {
  terminal_mode = {
    normal_mode = {"<M-q>"},                    -- Enter normal mode
    insert_file_path = {"<C-p>"},               -- Insert current file path
    insert_all_buffers = {"<C-p><C-p>"},        -- Insert all buffer paths
    new_lines = {"<S-CR>"},                     -- Insert new lines
    submit = {"<C-s>", "<C-CR>"},               -- Submit command
    enter = {"<CR>"},                           -- Send Enter key
    help = {"<M-?>", "??", "\\"},             -- Show help
    toggle_fullscreen = {"<C-f>"},              -- Toggle fullscreen
    hide = {"<C-q>"},                           -- Hide window (keep process)
    close = {"<C-S-q>"}                         -- Close window (kill process)
  },
  normal_mode = {
    toggle_fullscreen = {"<C-f>"},              -- Toggle fullscreen
    hide = {"<C-q>"},                           -- Hide window (keep process)
    close = {"<C-S-q>"}                         -- Close window (kill process)
  }
}
```

## Ask Actions Schema

```lua
actions = {
  send = function(keys) end,     -- Send text/keys to terminal via chansend
  submit = function() end,       -- Send Enter key (auto-submit)
  newline = function() end,       -- Send newline character
  focus_file = function() end,    -- Move focus to file window (actions continue)
}
```

## Ask Context Data Schema

```lua
AskData = {
  file = "string",          -- Absolute path of the current file
  relative_file = "string", -- Path relative to current directory
  start_line = number,      -- 1-indexed start line (from selection or cursor)
  end_line = number,        -- 1-indexed end line (= start_line if no selection)
  selection = "string|nil", -- Selected text content (nil if no visual selection)
  filetype = "string",      -- vim.bo.filetype of the source buffer
  question = "string",      -- The user's typed question (set by ask.lua after submit)
}
```

## Global Configuration

```lua
{
  integrations = {},              -- Array of Integration configurations
  show_help_on_open = true,       -- Show help on terminal open
  new_lines_amount = 2,           -- Newlines after submit
  window_width = 34,              -- Default width (percentage or absolute)
  window_padding = 0,               -- Horizontal padding
  border = "none",                -- Border style
  floating = false,                 -- Floating window mode
  terminal_keys = { ... },        -- Default key mappings
  start_insert_on_click = false,  -- Re-enter insert on click
  list_buffer = false,              -- List terminal in bufferline
  env = {},                       -- Default env overrides
  unset_env = {},                 -- Default env removals
}
```

## Merge Rules

1. Global defaults apply to all integrations
2. Per-integration values override global defaults
3. `terminal_keys`: per-section override with key-by-key merge within section
4. `env`: merged via `vim.tbl_extend("force", process_env, global_env, integration_env)`. NOTE: `TERM` and `COLORTERM` are normalized to safe defaults (`xterm-256color` / `truecolor`) before the merge, unless explicitly provided in `env`.
5. `unset_env`: applied after merge, removes specified keys
