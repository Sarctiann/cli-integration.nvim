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
- [snacks.nvim](https://github.com/folke/snacks.nvim) (for terminal and notifications)

> **NOTE**: This plugin depends on [Snacks.nvim](https://github.com/folke/snacks.nvim)
> for terminal management and notifications.

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
--- @module 'Cli-Integration'
{
  "Sarctiann/cli-integration.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
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
  dependencies = {
    "folke/snacks.nvim",
  },
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
  requires = { "folke/snacks.nvim" },
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
  window_width = 64,
  floating = false,  -- Whether to open terminal in floating window
  terminal_keys = {
    terminal_mode = {
      normal_mode = { "<M-q>" },
      insert_file_path = { "<C-p>" },
      insert_all_buffers = { "<C-p><C-p>" },
      new_lines = { "<CR>" },
      submit = { "<C-s>" },
      enter = { "<tab>" },
      help = { "<M-?>", "??", "\\\\" },
      toggle_width = { "<C-f>" },
    },
    normal_mode = {
      hide = { "<Esc>" },
      toggle_width = { "<C-f>" },
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
  window_width = 64,
  show_help_on_open = true,

  integrations = {
    {
      name = "CursorAgent",
      cli_cmd = "cursor-agent",
      -- Uses global defaults: window_width = 64, show_help_on_open = true
    },
    {
      name = "Claude",
      cli_cmd = "claude",
      window_width = 80,  -- Overrides global default for this integration
      -- Still uses global show_help_on_open = true
    },
  },
})
```

### Configuration Options

#### Global Options (applied to all integrations)

| Option              | Type      | Default   | Description                                                                   |
| ------------------- | --------- | --------- | ----------------------------------------------------------------------------- |
| `integrations`      | `table[]` | `{}`      | **Required**: Array of integration configurations                             |
| `show_help_on_open` | `boolean` | `true`    | Default: Show help screen when terminal opens                                 |
| `new_lines_amount`  | `number`  | `2`       | Default: Number of new lines to insert after command submission               |
| `window_width`      | `number`  | `64`      | Default: Width for the terminal window                                        |
| `floating`          | `boolean` | `false`   | Default: Whether to open terminal in floating window                          |
| `terminal_keys`     | `table`   | See below | Default: Key mappings for the CLI terminal window (all values must be arrays) |

#### Integration Options (can override global defaults)

Each integration in the `integrations` array can have:

| Option              | Type      | Default         | Description                                                                                                     |
| ------------------- | --------- | --------------- | --------------------------------------------------------------------------------------------------------------- |
| `name`              | `string`  | **Required**    | Name for the integration (used for autocompletion in commands)                                                  |
| `cli_cmd`           | `string`  | **Required**    | CLI command name to execute (e.g., "cursor-agent")                                                              |
| `show_help_on_open` | `boolean` | Inherits global | Override: Show help screen when terminal opens                                                                  |
| `new_lines_amount`  | `number`  | Inherits global | Override: Number of new lines to insert after command submission                                                |
| `window_width`      | `number`  | Inherits global | Override: Width for the terminal window                                                                         |
| `floating`          | `boolean` | Inherits global | Override: Whether to open terminal in floating window                                                           |
| `keep_open`         | `boolean` | `false`         | Whether to keep the terminal open after execution (not auto-closing)                                            |
| `start_with_text`   | `string`  | `nil`           | Text to insert when terminal is ready (searches for `ready_text_flag` or `cli_cmd`)                             |
| `ready_text_flag`   | `string`  | `nil`           | Text flag to search in terminal output (first 10 lines) to detect readiness. If not set, searches for `cli_cmd` |
| `format_paths`      | `function` | `nil`         | Function to format file paths when inserting (receives path string, returns formatted string). If not set, uses `"@" .. path` |
| `terminal_keys`     | `table`   | Inherits global | Override: Key mappings for the CLI terminal window                                                              |

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
| `new_lines`          | `{ "<CR>" }`                | Insert new lines                    |
| `submit`             | `{ "<C-s>" }`               | Submit command/message              |
| `enter`              | `{ "<tab>" }`               | Enter key                           |
| `help`               | `{ "<M-?>", "??", "\\\\" }` | Show help (multiple keys supported) |
| `toggle_width`       | `{ "<C-f>" }`               | Toggle window width                 |

#### Normal Mode Keys

| Key            | Default       | Description         |
| -------------- | ------------- | ------------------- |
| `hide`         | `{ "<Esc>" }` | Hide terminal       |
| `toggle_width` | `{ "<C-f>" }` | Toggle window width |

#### Example: Custom Key Configuration

```lua
require("cli-integration").setup({
  -- Global key configuration (applied to all integrations)
  terminal_keys = {
    terminal_mode = {
      submit = { "<C-s>", "<leader><CR>" },  -- Multiple keys for submit
      help = { "??", "F1" },              -- Custom help keys
      toggle_width = { "<C-f>", "<C-w>" }, -- Multiple toggle options
    },
    normal_mode = {
      hide = { "<Esc>", "q" },            -- Multiple hide options
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
  window_width = 64,
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
      start_with_text = "init\n",  -- Insert this text when terminal is ready
      ready_text_flag = "Ready>",  -- Look for this flag in first 10 lines
    },
  },
})
```

**About `start_with_text` and `ready_text_flag`:**

- `start_with_text`: Text that will be automatically inserted into the terminal when it's ready. If not set, no text is inserted.
- `ready_text_flag`: A string pattern to search for in the first 10 lines of terminal output to detect when the CLI tool is ready. If not set, the plugin searches for `cli_cmd` instead.

#### Multiple Integrations with Per-Integration Overrides

```lua
require("cli-integration").setup({
  -- Global defaults
  window_width = 64,
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
      window_width = 80,  -- Override global default
      show_help_on_open = false,  -- Override global default
      floating = true,  -- This one opens in a floating window
    },
    {
      name = "MyCustomTool",
      cli_cmd = "my-custom-tool",
      window_width = 100,
      keep_open = true,  -- Keep terminal open after execution
      start_with_text = "Hello!\n",  -- Insert this text when terminal is ready
      ready_text_flag = "Ready>",  -- Search for this flag in first 10 lines
      terminal_keys = {  -- Override global terminal_keys
        terminal_mode = {
          submit = { "<C-s>" },
          -- ... other keys inherit from global defaults
        },
        normal_mode = {
          hide = { "<Esc>" },
        },
      },
    },
  },
})
```

## 🎮 Usage

### Important Notes

- **⚠️ The main commands are `:CLIIntegration open_cwd` and `:CLIIntegration open_root`.
  Each integration will open its own terminal (`win` and `buf`) or toggle to it if it's already open** This is handled by [Snacks.nvim](https://github.com/folke/snacks.nvim)'s `terminal()`.
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

| Keymap                  | Description                           |
| ----------------------- | ------------------------------------- |
| `<C-s>` or `<CR><CR>`   | Submit command/message                |
| `<M-q>` or `<Esc><Esc>` | Enter normal mode                     |
| `<C-p>`                 | Attach current file path              |
| `<C-p><C-p>`            | Attach all open buffer paths          |
| `<C-f>`                 | Toggle window width (expand/collapse) |
| `<M-?>` or `??` or `\\` | Show help                             |
| `<C-c>`                 | Clear/Stop/Close                      |
| `<C-d>`                 | Close terminal                        |
| `<C-r>`                 | Review changes                        |
| `<CR>`                  | New line                              |

#### Normal Mode (in terminal)

| Keymap                                   | Description                           |
| ---------------------------------------- | ------------------------------------- |
| `q` or `<Esc>`                           | Hide terminal                         |
| `<C-f>`                                  | Toggle window width (expand/collapse) |
| All other normal mode keys work as usual |                                       |

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
    { name = "Claude", cli_cmd = "claude", window_width = 80 },
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
      start_with_text = "Hello, world!\n",  -- Insert this when ready
      ready_text_flag = "Ready>",  -- Look for this in first 10 lines
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
      -- Custom function to format paths when inserting
      format_paths = function(path)
        -- Example: Wrap path in quotes
        return '"' .. path .. '"'
        -- Example: Use a different prefix
        -- return "file://" .. path
        -- Example: Use markdown link format
        -- return "[" .. vim.fn.fnamemodify(path, ":t") .. "](" .. path .. ")"
      end,
    },
  },
})
```

**About `format_paths`:**

- The function receives a single parameter: the file path (string)
- It should return a formatted string that will be inserted into the terminal
- If not provided, the default format is `"@" .. path` (e.g., `@path/to/file.txt`)
- This function is used when:
  - Inserting the current file path (`<C-p>`)
  - Inserting all open buffer paths (`<C-p><C-p>`)

## 💡 Tips

- **Attach Multiple Files**: Use `<C-p><C-p>` to quickly attach all your open buffers
- **Quick Submit**: Double-tap `<CR>` or use `<C-s>` to submit without leaving insert mode
- **Context Switching**: Use `:CLIIntegration open_cwd` vs `:CLIIntegration open_root`
  depending on whether you want file-level or project-level context
- **Integration Selection**: Specify the integration name as the second argument (e.g., `:CLIIntegration open_root CursorAgent`)
  Use autocompletion (Tab) to see available integration names
- **Pass CLI Arguments**: Add arguments after the integration name (e.g., `:CLIIntegration open_cwd MyTool --verbose`)
- **Floating vs Side Panel**: Use `floating = true` for floating windows, `false` for side panels (right side)
- **Custom Initialization**: Use `start_with_text` to automatically insert text when terminal is ready
- **Readiness Detection**: Configure `ready_text_flag` to customize how the plugin detects when your CLI tool is ready
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
        └── help.lua          # Help system
```

## 🤝 Contributing

Contributions are welcome! Feel free to submit issues and pull requests.

## 📄 License

MIT License - see [LICENSE](./LICENSE) file for details

## 🙏 Acknowledgments

- [snacks.nvim](https://github.com/folke/snacks.nvim) - For terminal and notification utilities
- The Neovim community for inspiration and support

---

Made with ❤️ for the Neovim community
