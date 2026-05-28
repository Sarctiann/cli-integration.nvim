# 🔧 cli-integration.nvim

A Neovim plugin that seamlessly integrates any command-line tool into your Neovim workflow, providing an interactive terminal interface for CLI tools directly within your editor.

> **Note**: This plugin is a generic wrapper/integration tool for any CLI application.
> You can configure multiple CLI integrations, each with its own `cli_cmd` and settings.

> This plugin aims to generalize the ability to integrate external CLIs into the Neovim workflow,
> using the [cursor-agent.nvim](https://github.com/Sarctiann/cursor-agent.nvim) implementation as a base.
> Naturally, being a generalization, it lacks the ability to have specific commands,
> as the goal is for it to be agnostic to the command-line tool being integrated.

## ✨ Features

- 🚀 **Quick Access**: Open CLI tool terminal with simple keymaps
- 📁 **Smart Context**: Automatically attach current file or project root
- 🔄 **Multiple Modes**: Work in current directory, project root, or custom paths
- 📋 **Buffer Management**: Easily attach single or multiple open buffers
- ⚡ **Interactive Terminal**: Full terminal integration with custom keymaps
- 🎯 **Flexible Configuration**: Configure multiple CLI tools with global and per-integration settings
- 💡 **Helpful Guidance**: Shows configuration help if CLI command is not set
- 🔀 **Multiple Integrations**: Run multiple CLI tools simultaneously, each with its own configuration
- 🪟 **Floating Windows**: Configure terminals to open in floating windows or side panels
- 📝 **Custom Initialization**: Automatically insert custom text when terminal is ready
- 🎛️ **CLI Arguments**: Pass command-line arguments directly to your CLI tools
- 🔍 **Smart Readiness Detection**: Customize how the plugin detects when your CLI tool is ready

## 📋 Requirements

- Neovim >= 0.9.0
- CLI tool(s) installed and available in your `$PATH` (configured via `integrations[].cli_cmd`)

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
--- @module 'Cli-Integration'
{
  "Sarctiann/cli-integration.nvim",
  --- @type Cli-Integration.Config
  opts = {
    integrations = {
      { name = "MyTool", cli_cmd = "your-cli-tool" },  -- Required: name and cli_cmd
      -- Add more integrations here
    },
    -- Configure global defaults here (applied to all integrations)
  },
}
```

### For local development

```lua
--- @module 'Cli-Integration'
{
  dir = "~/.config/nvim/lua/custom_plugins/cli-integration.nvim",
  --- @type Cli-Integration.Config
  opts = {
    integrations = {
      { name = "MyTool", cli_cmd = "your-cli-tool" },  -- Required: name and cli_cmd
      -- Add more integrations here
    },
    -- Configure global defaults here (applied to all integrations)
  },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "Sarctiann/cli-integration.nvim",
  config = function()
    require("cli-integration").setup({
      integrations = {
        { name = "MyTool", cli_cmd = "your-cli-tool" },  -- Required: name and cli_cmd
        -- Add more integrations here
      },
      -- Configure global defaults here (applied to all integrations)
    })
  end
}
```

## ⚙️ Configuration

### Minimum Required Configuration

The only required option is `integrations`, which is an array of integration configurations. Each integration must have both `name` and `cli_cmd`:

```lua
require("cli-integration").setup({
  integrations = {
    { name = "CursorAgent", cli_cmd = "cursor-agent" },  -- Required: name and cli_cmd
  },
})
```

> **Important**: If `integrations` is empty or not configured, the plugin will display a helpful message
> indicating the minimum configuration required when you try to open the terminal.

### Default Configuration

```lua
-- These are the default values; you can use `setup({})` to use defaults
require("cli-integration").setup({
  integrations = {},  -- Array of integrations (each must have name and cli_cmd)
  -- Global defaults (applied to all integrations unless overridden):
  show_help_on_open = true,
  new_lines_amount = 2,
  window_width = 34,  -- Percentage (0-100) or absolute width (>100)
  window_padding = 0,  -- Horizontal padding in columns (0 = no padding)
  border = "none",  -- Border style (none/single/double/rounded/solid/shadow)
  floating = false,  -- Whether to open terminal in floating window
  env = {},  -- Default environment overrides for all integration jobs
  unset_env = {},  -- Default environment variables to remove from integration jobs
  terminal_keys = {
    terminal_mode = {
      normal_mode = { "<M-q>" },
      insert_file_path = { "<C-p>" },
      insert_all_buffers = { "<C-p><C-p>" },

      -- You might want to change these "enter" related keys
      -- depending on your configuration or your terminal behavior
      new_lines = { "<S-CR>" },
      submit = { "<C-s>", "<C-CR>" },
      enter = { "<CR>" },

      help = { "<M-?>", "??", "\\\\" },
      toggle_fullscreen = { "<C-f>" },
      hide = { "<C-q>" },  -- Hide terminal (keeps process alive)
      close = { "<C-S-q>" },  -- Close terminal and kill process
    },
    normal_mode = {
      hide = { "<C-q>" },  -- Hide terminal (keeps process alive)
      toggle_fullscreen = { "<C-f>" },
      close = { "<C-S-q>" },  -- Close terminal and kill process
    },
  },
})
```

### How Configuration Works

The plugin supports **global defaults** and **per-integration overrides**:

- **Global defaults**: Set at the root level of the config. These apply to all integrations.
- **Per-integration overrides**: Set within each integration object. These override the global defaults for that specific integration.

```lua
require("cli-integration").setup({
  -- Global defaults (applied to all integrations)
  window_width = 34,  -- 34% of editor width
  show_help_on_open = true,

  integrations = {
    {
      name = "CursorAgent",
      cli_cmd = "cursor-agent",
      -- Uses global defaults: window_width = 34%, show_help_on_open = true
    },
    {
      name = "Claude",
      cli_cmd = "claude",
      window_width = 50,  -- Overrides global default: 50% of editor width
      -- Still uses global show_help_on_open = true
    },
  },
})
```

## Terminology (glossary)

- Integration Window: The plugin's terminal window. It can open as a centered floating window (`floating`), a right-side panel (`sidebar`), or a fullwidth variant of the sidebar (`fullwidth`).

These terms are used throughout the documentation and the codebase (AGENTS.md contains the canonical definitions and invariants).

### Configuration Options

#### Global Options (applied to all integrations)

| Option              | Type       | Default   | Description                                                                           |
| ------------------- | ---------- | --------- | ------------------------------------------------------------------------------------- |
| `integrations`      | `table[]`  | `{}`      | **Required**: Array of integration configurations                                     |
| `show_help_on_open` | `boolean`  | `true`    | Default: Show help screen when terminal opens                                         |
| `new_lines_amount`  | `number`   | `2`       | Default: Number of new lines to insert after command submission                       |
| `window_width`      | `number`   | `34`      | Default: Width for terminal window (percentage 0-100, or absolute >100)               |
| `window_padding`    | `number`   | `0`       | Default: Horizontal padding in columns (adds empty space on left and right)           |
| `border`            | `string`   | `"none"`  | Default: Border style ("none", "single", "double", "rounded", "solid", "shadow")      |
| `floating`          | `boolean`  | `false`   | Default: Whether to open terminal in floating window                                  |
| `env`               | `table`    | `{}`      | Default: Environment overrides merged on top of inherited process environment         |
| `unset_env`         | `string[]` | `{}`      | Default: Environment variable names removed from the spawned terminal job environment |
| `terminal_keys`     | `table`    | See below | Default: Key mappings for the CLI terminal window (all values must be arrays)         |

#### Integration Options (can override global defaults)

Each integration in the `integrations` array can have:

| Option                  | Type       | Default         | Description                                                                                                                                                                                                                                                                                                                                            |
| ----------------------- | ---------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`                  | `string`   | **Required**    | Name for the integration (used for autocompletion in commands)                                                                                                                                                                                                                                                                                         |
| `cli_cmd`               | `string`   | **Required**    | CLI command name to execute (e.g., "cursor-agent")                                                                                                                                                                                                                                                                                                     |
| `show_help_on_open`     | `boolean`  | Inherits global | Override: Show help screen when terminal opens                                                                                                                                                                                                                                                                                                         |
| `new_lines_amount`      | `number`   | Inherits global | Override: Number of new lines to insert after command submission                                                                                                                                                                                                                                                                                       |
| `window_width`          | `number`   | Inherits global | Override: Width for terminal window (percentage 0-100, or absolute >100)                                                                                                                                                                                                                                                                               |
| `window_padding`        | `number`   | Inherits global | Override: Horizontal padding in columns (adds empty space on left and right)                                                                                                                                                                                                                                                                           |
| `border`                | `string`   | Inherits global | Override: Border style ("none", "single", "double", "rounded", "solid", "shadow"). Default is "none" for sidebar, "rounded" when expanded or floating                                                                                                                                                                                                  |
| `floating`              | `boolean`  | Inherits global | Override: Whether to open terminal in floating window                                                                                                                                                                                                                                                                                                  |
| `env`                   | `table`    | Inherits global | Override: Environment overrides merged on top of inherited process environment                                                                                                                                                                                                                                                                         |
| `unset_env`             | `string[]` | Inherits global | Override: Environment variable names removed from the spawned terminal job environment                                                                                                                                                                                                                                                                 |
| `keep_open`             | `boolean`  | `false`         | Whether to keep the terminal open after execution (not auto-closing)                                                                                                                                                                                                                                                                                   |
| `start_insert_on_click` | `boolean`  | `false`         | Re-enter insert mode when clicking inside the terminal while in normal mode                                                                                                                                                                                                                                                                            |
| `list_buffer`           | `boolean`  | `false`         | List the terminal buffer in the bufferline as `[name]`. Sidebar only: shifts window 1 row down to avoid overlap. When `start_insert_on_click=true` and the integration window is hidden (e.g., buffer selected via bufferline), clicking on a regular window will correctly move focus there instead of forcing insert mode in the integration window. |
| `open_delay`            | `number`   | `0`             | Milliseconds to wait before creating the terminal window. Useful when `on_open` triggers an external process that needs time to start before the terminal connects                                                                                                                                                                                     |
| `start_doing`           | `function` | `nil`           | Called when terminal is ready. Signature: `function(visual_text, actions)`. Actions: `send_line(text?)`, `send_keys(keys)`, `wait(ms)`. Does not return a value.                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `cli_ready_flags`       | `table`    | See below       | Configuration for detecting readiness (search string, starting line, and number of lines to inspect)                                                                                                                                                                                                                                                   |
| `format_paths`          | `function` | `nil`           | Callback to format and insert file paths. Receives `(paths, actions)` where `paths` is a string array and `actions` has `send_line(text)`, `send_keys(keys)`, `wait(ms)`, and `for_each_path(fn)`. Does not return a value. If not set, raw paths are inserted                                                                                         |
| `on_open`               | `function` | `nil`           | Called before the terminal is created. Receives `(integration, working_dir)`. Use for pre-launch setup (e.g., writing config files with dynamic values)                                                                                                                                                                                                |
| `on_close`              | `function` | `nil`           | Called after the terminal process exits. Receives `(integration, working_dir)`. Use for cleanup tasks (e.g., removing temporary config files)                                                                                                                                                                                                          |
| `ask_title`             | `string`   | `"Ask "..name`  | Custom title for the floating input window used by the Ask hook                                                                                                                                                                                                                                                                                        |
| `terminal_keys`         | `table`    | Inherits global | Override: Key mappings for the CLI terminal window                                                                                                                                                                                                                                                                                                     |

## 💬 Ask Hook

The Ask hook provides a quick way to send context-aware questions to CLI integrations from within Neovim.

### Usage

```lua
-- Via Lua API
require("cli-integration").hooks.ask("Opencode")

-- Via keymap (in your config)
vim.keymap.set("n", "<leader>aq", function()
  require("cli-integration").hooks.ask("Opencode")
end, { desc = "Ask Opencode" })
```

When invoked, a floating input window appears near the cursor. Type your question and press Enter to send it to the integration terminal.

### Features

- **Two-window architecture**: Outer window displays border, title, and "❯ " icon. Inner window handles text input. No prefix management needed — Backspace works naturally.
- **Visual selection**: If you have text selected in visual mode, the selection is captured as context
- **Sequential flow**: Context captured → terminal opened → focus returned to file → selection restored → input shown

### Configuration

```lua
{
  cli_cmd = "opencode",
  name = "Opencode",
  -- Override the default "Ask {name}" title
  ask_title = "Ask AI",  -- default: "Ask " .. integration.name

  -- Custom handler for submitted questions
  on_ask_submit = function(data, actions)
    -- data.file          — absolute file path
    -- data.relative_file — relative file path
    -- data.filename      — just the filename (e.g. "main.lua")
    -- data.start_line    — start line number
    -- data.end_line      — end line number
    -- data.selection     — selected text (nil if no selection)
    -- data.filetype      — file type
    -- data.question      — user's typed question

    -- actions.send_line(text) — send text followed by newline (text defaults to "")
    -- actions.send_keys(keys) — send key sequences ("<CR>", "<Esc>", "<C-c>", etc.)
    -- actions.wait(ms)        — block for milliseconds before next action
    -- actions.submit()        — send Enter key
    -- actions.focus_file()    — focus the file window

    actions.send_line(data.question .. "\n\nFile: " .. data.relative_file)
    actions.submit()
  end,
}
```

### Default Behavior

If `on_ask_submit` is not configured, the built-in default handler sends a formatted message:

```
<question>

<relative_file>:L<start_line>-L<end_line>  (with selection)
<selection text>
```

or:

```
<question>

<relative_file>:L<start_line>  (without selection)
```

The terminal window is auto-focused after submission unless `actions.focus_file()` is called.

#### Window Width Configuration

The `window_width` option supports two modes:

- **Percentage mode** (values 0-100): The window width is calculated as a percentage of the editor width
  - `34` = 34% of editor width (default)
  - `50` = 50% of editor width
  - `0.5` = 0.5% of editor width (for very small values)

- **Absolute mode** (values > 100): The window width is set to an exact number of characters
  - `150` = 150 characters wide (useful for very wide terminals)

Examples:

```lua
window_width = 34,   -- 34% of editor width (default)
window_width = 50,   -- 50% of editor width
window_width = 150,  -- 150 characters (absolute)
```

#### Window Padding Configuration

The `window_padding` option adds visual spacing on the left and right sides of the terminal content:

- **Value**: Number of columns (characters) to use as padding
- **Default**: `0` (no padding)
- **Recommended**: `1` for a cleaner look with TUI applications

How it works:

- The terminal window width is reduced by `padding * 2` (left + right)
- Left padding is created using `foldcolumn`
- Right padding is created by limiting the terminal's `COLUMNS` environment variable

Example:

```lua
window_padding = 1,  -- Adds 1 character padding on each side
```

#### Border Configuration

The `border` option controls the border style of the terminal window:

- **Values**: `"none"`, `"single"`, `"double"`, `"rounded"`, `"solid"`, `"shadow"`
- **Default**: `"none"` for sidebar mode, `"rounded"` for floating windows and when expanded
- **Note**: When you toggle the window width to maximum (Ctrl+f), the border automatically changes to `"rounded"`

Examples:

```lua
border = "none",     -- No border (default for sidebar)
border = "rounded",  -- Rounded corners (default for floating)
border = "single",   -- Single line border
border = "double",   -- Double line border
```

### `terminal_keys` Structure

The `terminal_keys` option allows you to customize all key mappings for the CLI terminal window.
**All values must be arrays**, even if you only want to configure one key combination. This allows you to set
multiple key combinations for the same action.

#### Terminal Mode Keys

| Key                  | Default                     | Description                         |
| -------------------- | --------------------------- | ----------------------------------- |
| `normal_mode`        | `{ "<M-q>" }`               | Enter normal mode                   |
| `insert_file_path`   | `{ "<C-p>" }`               | Insert current file path            |
| `insert_all_buffers` | `{ "<C-p><C-p>" }`          | Insert all open buffer paths        |
| `new_lines`          | `{ "<S-CR>" }`              | Insert new lines                    |
| `submit`             | `{ "<C-s>", "<C-CR>" }`     | Submit command/message              |
| `enter`              | `{ "<CR>" }`                | Enter key                           |
| `help`               | `{ "<M-?>", "??", "\\\\" }` | Show help (multiple keys supported) |
| `toggle_fullscreen`  | `{ "<C-f>" }`               | Toggle fullscreen                   |
| `hide`               | `{ "<C-q>" }`               | Hide terminal (keeps process alive) |
| `close`              | `{ "<C-S-q>" }`             | Close terminal and kill process     |

#### Normal Mode Keys

| Key                 | Default         | Description                         |
| ------------------- | --------------- | ----------------------------------- |
| `hide`              | `{ "<C-q>" }`   | Hide terminal (keeps process alive) |
| `toggle_fullscreen` | `{ "<C-f>" }`   | Toggle fullscreen                   |
| `close`             | `{ "<C-S-q>" }` | Close terminal and kill process     |

#### Example: Custom Key Configuration

```lua
require("cli-integration").setup({
  -- Global key configuration (applied to all integrations)
  terminal_keys = {
    terminal_mode = {
      submit = { "<C-s>", "<leader><CR>" },  -- Multiple keys for submit
      help = { "??", "F1" },                 -- Custom help keys
      toggle_fullscreen = { "<C-f>", "<C-w>" },   -- Multiple toggle options
      hide = { "<C-q>", "<Esc>" },           -- Multiple hide options
      close = { "<C-S-q>", "<leader>q" },    -- Multiple close options
    },
    normal_mode = {
      hide = { "<C-q>", "q" },               -- Multiple hide options
      close = { "<C-S-q>", "<leader>q" },    -- Multiple close options
    },
  },
  integrations = {
    { name = "MyTool", cli_cmd = "my-cli-tool" },
  },
})
```

### Example Configurations

#### Single Integration

```lua
require("cli-integration").setup({
  integrations = {
    { name = "CursorAgent", cli_cmd = "cursor-agent" },
  },
})
```

#### Multiple Integrations with Global Defaults

```lua
require("cli-integration").setup({
  -- Global defaults applied to all integrations
  window_width = 34,  -- 34% of editor width
  show_help_on_open = true,
  floating = false,  -- All terminals open on the right side

  integrations = {
    { name = "CursorAgent", cli_cmd = "cursor-agent" },
    { name = "Claude", cli_cmd = "claude" },
  },
})
```

#### Advanced Configuration with Custom Text and Flags

```lua
require("cli-integration").setup({
  integrations = {
    {
      name = "MyTool",
      cli_cmd = "my-tool",
      floating = true,  -- Open in floating window
      keep_open = true,  -- Don't auto-close after execution
      start_doing = function(_, actions) actions.send_line("init") end,  -- Called when terminal is ready
      cli_ready_flags = {
        search_for = "Ready>",  -- Look for this flag
        from_line = 1,          -- Starting from line 1
        lines_amt = 10,         -- Check 10 lines
      },
    },
  },
})
```

#### Environment Inheritance and Overrides

Terminal jobs inherit Neovim's process environment by default (including variables like `$NVIM`, `$TERM`, and tmux variables when present).

Use `env` and `unset_env` only when a specific tool requires explicit adjustments:

```lua
require("cli-integration").setup({
  -- Optional global environment defaults
  env = {
    EXAMPLE_FLAG = "1",
  },
  unset_env = {
    "EXAMPLE_UNWANTED_VAR",
  },

  integrations = {
    {
      name = "OpenCode",
      cli_cmd = "opencode",
      -- Optional per-integration environment tuning
      env = {
        OPENCODE_MODE = "embedded",
      },
      unset_env = {
        -- e.g. "TMUX" only if a specific setup needs it
      },
    },
  },
})
```

**About `start_doing` and `cli_ready_flags`:**

- `start_doing`: A function that receives `(visual_text, actions)` where actions has `send_line(text?)`, `send_keys(keys)`, and `wait(ms)`.
- The function is called when the terminal is detected as ready (via `cli_ready_flags`).
- Use `actions.send_line()` to insert text, `actions.send_keys()` for key sequences, and `actions.wait()` for delays between actions.
- If no `start_doing` is set but `visual_text` is present from a visual selection, the visual text is inserted directly.
- The `wait()` method yields execution via coroutine, allowing the terminal to process inputs between actions.
- `cli_ready_flags`: A table configuration to detect when the CLI tool is ready:
  - `search_for`: A string pattern to search for in terminal output. If not set or empty, the plugin searches for `cli_cmd` instead.
  - `from_line`: The line number to start searching from (1-based, default: 1).
  - `lines_amt`: The number of lines to inspect (default: 5).

#### Visual Selection Support

You can send selected text to the terminal when opening it. Use `start_doing` to handle visual selections:

````lua
require("cli-integration").setup({
  integrations = {
    {
      name = "MyTool",
      cli_cmd = "my-tool",
      -- Function receives (visual_text, actions)
      start_doing = function(visual_text, actions)
        if visual_text then
          -- Transform visual selection (e.g., wrap in code block)
          actions.send_line("```\n" .. visual_text .. "```\n")
          return
        end
        -- Default text when no visual selection
        actions.send_line("Hello!")
      end,
    },
  },
})
````

**Usage:**

1. Select text in visual mode (V, v, or Ctrl-v)
2. Run `:'<,'>CLIIntegration` (or `:'<,'>CLIIntegration open_cwd`, etc.)
3. The selected text will be passed to `start_doing` as `visual_text`

**Note:**

- When `start_doing` is set, it receives the visual selection as the `visual_text` parameter (or `nil` if none)
- When `start_doing` is **not set**, the visual selection is inserted as-is

#### Multiple Integrations with Per-Integration Overrides

```lua
require("cli-integration").setup({
  -- Global defaults
  window_width = 34,  -- 34% of editor width
  show_help_on_open = true,
  floating = false,  -- All terminals open on the right side by default

  integrations = {
    {
      name = "CursorAgent",
      cli_cmd = "cursor-agent",
      -- Uses global defaults
    },
    {
      name = "Claude",
      cli_cmd = "claude",
      window_width = 50,  -- Override: 50% of editor width
      show_help_on_open = false,  -- Override global default
      floating = true,  -- This one opens in a floating window
    },
    {
      name = "MyCustomTool",
      cli_cmd = "my-custom-tool",
      window_width = 150,  -- Absolute width: 150 characters (>100 = absolute)
      keep_open = true,  -- Keep terminal open after execution
      start_doing = function(_, actions) actions.send_line("Hello!") end,  -- Called when terminal is ready
      cli_ready_flags = { search_for = "Ready>", from_line = 1, lines_amt = 10 },
      terminal_keys = {  -- Override global terminal_keys (per-section with key-by-key merge)
        terminal_mode = {
          submit = { "<C-s>" },
          hide = { "<Esc>" },  -- Only this key is overridden; other terminal_mode keys inherit from global defaults
        },
        normal_mode = {
          hide = { "<Esc>", "q" },  -- Custom hide keys for this integration
          close = { "<leader>q" },  -- Custom close key for this integration
        },
      },
    },
  },
})
```

## 🎮 Usage

### Important Notes

- **⚠️ The main commands are `:CLIIntegration open_cwd` and `:CLIIntegration open_root`.
  Each integration will open its own terminal (`win` and `buf`) or toggle to it if it's already open**.
- **Multiple Integrations**: You can run multiple CLI tools simultaneously. Each integration maintains its own terminal instance and configuration.
- **Integration Names**: Each integration must have a unique `name` (used for autocompletion). Commands use the first integration by default if no name is specified.
- **Configuration Required**: If `integrations` is empty or missing `name` or `cli_cmd`, opening the terminal will display a helpful message
  showing the minimum configuration needed.
- **Global vs Per-Integration**: Global configuration options apply to all integrations. Each integration can override these defaults.
- For convenience, the default "Enter" key (`<CR>`) is remapped to the "Tab" key (`<Tab>`)
  You can change this to whatever you want by changing the `terminal_keys.terminal_mode.enter` keymap.

### Commands

The plugin provides a single command with multiple sub-commands:

```vim
:CLIIntegration [action] [integration_name] [cli_args...]
```

**Available actions:**

- `:CLIIntegration open_cwd` - Open in current file's directory (uses first integration if no name specified)
- `:CLIIntegration open_root` - Open in project root (git root) (uses first integration if no name specified)

**Examples:**

```vim
:CLIIntegration open_root CursorAgent
:CLIIntegration open_cwd Claude
:CLIIntegration open_root  " Uses first integration
:CLIIntegration open_cwd MyTool --flag value  " Pass arguments to CLI tool
:CLIIntegration open_root CursorAgent arg1 arg2 arg3  " Multiple arguments
```

**Passing Arguments to CLI Tools:**

You can pass additional arguments to the CLI tool by adding them after the integration name:

```vim
:CLIIntegration open_cwd MyTool --verbose --output=file.txt
:CLIIntegration open_root CursorAgent --mode interactive
```

The command supports autocompletion:

- After typing `:CLIIntegration `, you'll see available actions (`open_cwd`, `open_root`)
- After typing an action, you'll see available integration names

### Terminal Keymaps

Once the CLI tool terminal is open, you have access to special keymaps:

#### Terminal Mode

| Keymap                  | Description                                |
| ----------------------- | ------------------------------------------ |
| `<C-s>` or `<C-CR>`     | Submit command/message                     |
| `<M-q>`                 | Enter normal mode                          |
| `<C-p>`                 | Attach current file path                   |
| `<C-p><C-p>`            | Attach all open buffer paths               |
| `<C-f>`                 | Toggle window width (expand/collapse)      |
| `<M-?>` or `??` or `\\` | Show help                                  |
| `<C-q>`                 | Hide terminal window (keeps process alive) |
| `<C-S-q>`               | Close terminal window and kill process     |
| `<S-CR>`                | Insert new line                            |
| `<CR>`                  | Send Enter key                             |

#### Normal Mode (in terminal)

| Keymap                                   | Description                                |
| ---------------------------------------- | ------------------------------------------ |
| `<C-q>`                                  | Hide terminal window (keeps process alive) |
| `<C-S-q>`                                | Close terminal window and kill process     |
| `<C-f>`                                  | Toggle window width (expand/collapse)      |
| All other normal mode keys work as usual |                                            |

## 🚀 Quick Start

1. Install the plugin using your preferred package manager
2. Configure `integrations` with your CLI tool(s) (e.g., `integrations = { { name = "CursorAgent", cli_cmd = "cursor-agent" } }`)
3. Make sure your CLI tool(s) are installed and available in your `$PATH`
4. Open Neovim and use `:CLIIntegration open_root` or `:CLIIntegration open_cwd` to open your CLI tool
5. Type your command or question
6. Press `<C-s>` or `<CR><CR>` to submit
7. Use `<C-p>` to quickly attach files to the conversation

### Multiple Integrations Example

```lua
require("cli-integration").setup({
  integrations = {
    { name = "CursorAgent", cli_cmd = "cursor-agent" },
    { name = "Claude", cli_cmd = "claude", window_width = 50 },  -- 50% width
  },
})
```

This allows you to use both `cursor-agent` and `claude` simultaneously, each with its own terminal and configuration. You can specify which integration to use:

```vim
:CLIIntegration open_root CursorAgent
:CLIIntegration open_cwd Claude
:CLIIntegration open_cwd Claude --verbose  " Pass arguments to Claude
```

### Floating Windows Example

```lua
require("cli-integration").setup({
  floating = true,  -- All terminals open in floating windows by default
  integrations = {
    { name = "MyTool", cli_cmd = "my-tool" },
  },
})
```

Or configure per-integration:

```lua
require("cli-integration").setup({
  integrations = {
    { name = "Tool1", cli_cmd = "tool1", floating = true },   -- Floating
    { name = "Tool2", cli_cmd = "tool2", floating = false },  -- Side panel
  },
})
```

### Custom Initialization Text Example

```lua
require("cli-integration").setup({
  integrations = {
    {
      name = "MyTool",
      cli_cmd = "my-tool",
      start_doing = function(_, actions) actions.send_line("Hello, world!") end,  -- Called when ready
      cli_ready_flags = {
        search_for = "Ready>",  -- Look for this flag
        from_line = 1,          -- Starting from line 1
        lines_amt = 10,         -- Check 10 lines
      },
    },
  },
})
```

### Custom Path Formatting Example

```lua
require("cli-integration").setup({
  integrations = {
    {
      name = "MyTool",
      cli_cmd = "my-tool",
      -- Custom callback to format and insert paths
      format_paths = function(paths, actions)
        actions.for_each_path(function(path)
          return "@" .. path .. " "
        end)

        -- You can also use the imperative actions when you need it:
        -- actions.send_keys("<Esc>")
        -- actions.send_line("# done")
        -- actions.wait(50)
      end,
    },
  },
})
```

**About `format_paths`:**

- The callback receives two parameters:
  - `paths` — Array of file path strings (all paths to be inserted)
  - `actions` — Table with helper methods
- The callback does **not** return a value — it calls actions imperatively, just like `on_ask_submit`
- If not provided, paths are inserted as-is (with a trailing space for `<C-p>`, or one per line for `<C-p><C-p>`)
- This callback is used when:
  - Inserting the current file path (`<C-p>`)
  - Inserting all open buffer paths (`<C-p><C-p>`)

**Actions table:**

| Method          | Signature                          | Description                                     |
| --------------- | ---------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------ |
| `send_line`     | `fun(text: string?)`               | Send text followed by a newline to the terminal |
| `send_keys`     | `fun(keys: string)`                | Send Vim key sequences through chansend         |
| `wait`          | `fun(ms: number)`                  | Pause the callback for the given milliseconds   |
| `for_each_path` | `fun(fn: fun(path: string): string | nil)`                                           | Iterate all paths, call `fn(path)`, and insert any returned string into the terminal |

```lua
require("cli-integration").setup({
  integrations = {
    {
      name = "MyTool",
      cli_cmd = "my-tool",
      -- Example: transform visual selection with actions
      start_doing = function(visual_text, actions)
        if visual_text then
          -- Example: Add a prefix to each line
          local lines = vim.split(visual_text, "\n")
          for i, line in ipairs(lines) do
            lines[i] = "> " .. line
          end
          actions.send_line(table.concat(lines, "\n"))
        else
          -- Default text when no visual selection
          actions.send_line("init")
        end
      end,
    },
  },
})
```

**About `start_doing`:**

- The function receives two parameters: `visual_text` (string|nil) and `actions` (table)
- `visual_text` is the selected text when opening with visual selection, or `nil` otherwise
- `actions` has `send_line(text?)`, `send_keys(keys)`, and `wait(ms)` methods
- The function does not return a value — it calls actions imperatively
- When opening the terminal with a visual selection (e.g., `:'<,'>CLIIntegration`), `visual_text` will contain the selected text
- When opening normally, `visual_text` will be `nil`

## 💡 Tips

- **Attach Multiple Files**: Use `<C-p><C-p>` to quickly attach all your open buffers
- **Quick Submit**: Double-tap `<CR>` or use `<C-s>` to submit without leaving insert mode
- **Context Switching**: Use `:CLIIntegration open_cwd` vs `:CLIIntegration open_root`
  depending on whether you want file-level or project-level context
- **Integration Selection**: Specify the integration name as the second argument (e.g., `:CLIIntegration open_root CursorAgent`)
  Use autocompletion (Tab) to see available integration names
- **Pass CLI Arguments**: Add arguments after the integration name (e.g., `:CLIIntegration open_cwd MyTool --verbose`)
- **Floating vs Side Panel**: Use `floating = true` for floating windows, `false` for side panels (right side)
- **Custom Initialization**: Use `start_doing` to automatically run actions when terminal is ready
- **Readiness Detection**: Configure `cli_ready_flags` to customize how the plugin detects when your CLI tool is ready
- **Keep Terminal Open**: Set `keep_open = true` to prevent auto-closing after execution
- **Help Anytime**: Press `??` in terminal mode to see all available keymaps (shows config for current integration)
- **Multiple Tools**: Configure multiple CLI tools and switch between them. Each maintains its own terminal and settings.
- **Global Defaults**: Set common settings once at the global level, then override per-integration as needed.
- **Configuration Help**: If you forget to configure `integrations`, `name`, or `cli_cmd`, the plugin will show you
  the minimum configuration needed when you try to open the terminal

## 🏗️ Project Structure

```bash
cli-integration.nvim/
└── lua/
    └── cli-integration/
        ├── init.lua          # Main entry point and setup
        ├── config.lua        # Configuration management
        ├── terminal.lua      # Terminal management (supports multiple terminals)
        ├── commands.lua      # Command implementations
        ├── buffers.lua       # Buffer path management
        ├── keymaps.lua       # Terminal keymaps
        ├── autocmds.lua      # Autocommands
        ├── help.lua          # Help system
        ├── ask.lua           # Ask hook (context-aware questions)
        └── hooks.lua         # Shared hooks (session management, path helpers)
```

## 🤝 Contributing

Contributions are welcome! Feel free to submit issues and pull requests.

## 📄 License

MIT License - see [LICENSE](./LICENSE) file for details

## 🙏 Acknowledgments

- The Neovim community for inspiration and support

---

Made with ❤️ for the Neovim community

```

```
