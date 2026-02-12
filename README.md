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
      { cli_cmd = "your-cli-tool" },  -- Required: specify your CLI command
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
      { cli_cmd = "your-cli-tool" },  -- Required: specify your CLI command
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
        { cli_cmd = "your-cli-tool" },  -- Required: specify your CLI command
        -- Add more integrations here
      },
      -- Configure global defaults here (applied to all integrations)
    })
  end
}
```

## ⚙️ Configuration

### Minimum Required Configuration

The only required option is `integrations`, which is an array of integration configurations. Each integration must have a `cli_cmd`:

```lua
require("cli-integration").setup({
  integrations = {
    { cli_cmd = "cursor-agent" },  -- Required: your CLI command name
  },
})
```

> **Important**: If `integrations` is empty or not configured, the plugin will display a helpful message
> indicating the minimum configuration required when you try to open the terminal.

### Default Configuration

```lua
-- These are the default values; you can use `setup({})` to use defaults
require("cli-integration").setup({
  integrations = {},  -- Array of integrations (each must have cli_cmd)
  -- Global defaults (applied to all integrations unless overridden):
  show_help_on_open = true,
  new_lines_amount = 2,
  window_width = 64,
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
      cli_cmd = "cursor-agent",
      -- Uses global defaults: window_width = 64, show_help_on_open = true
    },
    {
      cli_cmd = "claude",
      window_width = 80,  -- Overrides global default for this integration
      -- Still uses global show_help_on_open = true
    },
  },
})
```

### Configuration Options

#### Global Options (applied to all integrations)

| Option              | Type      | Default   | Description                                                          |
| ------------------- | --------- | --------- | -------------------------------------------------------------------- |
| `integrations`      | `table[]` | `{}`      | **Required**: Array of integration configurations                    |
| `show_help_on_open` | `boolean` | `true`    | Default: Show help screen when terminal opens                        |
| `new_lines_amount`  | `number`  | `2`       | Default: Number of new lines to insert after command submission     |
| `window_width`      | `number`  | `64`      | Default: Width for the terminal window                               |
| `terminal_keys`     | `table`   | See below | Default: Key mappings for the CLI terminal window (all values must be arrays) |

#### Integration Options (can override global defaults)

Each integration in the `integrations` array can have:

| Option              | Type      | Default   | Description                                                          |
| ------------------- | --------- | --------- | -------------------------------------------------------------------- |
| `cli_cmd`           | `string`  | **Required** | CLI command name to execute (e.g., "cursor-agent")                |
| `show_help_on_open` | `boolean` | Inherits global | Override: Show help screen when terminal opens                    |
| `new_lines_amount`  | `number`  | Inherits global | Override: Number of new lines to insert after command submission  |
| `window_width`      | `number`  | Inherits global | Override: Width for the terminal window                            |
| `terminal_keys`     | `table`   | Inherits global | Override: Key mappings for the CLI terminal window                 |

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
    { cli_cmd = "my-cli-tool" },
  },
})
```

### Example Configurations

#### Single Integration

```lua
require("cli-integration").setup({
  integrations = {
    { cli_cmd = "cursor-agent" },
  },
})
```

#### Multiple Integrations with Global Defaults

```lua
require("cli-integration").setup({
  -- Global defaults applied to all integrations
  window_width = 64,
  show_help_on_open = true,
  
  integrations = {
    { cli_cmd = "cursor-agent" },
    { cli_cmd = "claude" },
  },
})
```

#### Multiple Integrations with Per-Integration Overrides

```lua
require("cli-integration").setup({
  -- Global defaults
  window_width = 64,
  show_help_on_open = true,
  
  integrations = {
    {
      cli_cmd = "cursor-agent",
      -- Uses global defaults
    },
    {
      cli_cmd = "claude",
      window_width = 80,  -- Override global default
      show_help_on_open = false,  -- Override global default
    },
    {
      cli_cmd = "my-custom-tool",
      window_width = 100,
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
- **Default Integration**: Commands use the first integration by default. You can specify which integration to use programmatically.
- **Configuration Required**: If `integrations` is empty or missing `cli_cmd`, opening the terminal will display a helpful message
  showing the minimum configuration needed.
- **Global vs Per-Integration**: Global configuration options apply to all integrations. Each integration can override these defaults.
- For convenience, the default "Enter" key (`<CR>`) is remapped to the "Tab" key (`<Tab>`)
  You can change this to whatever you want by changing the `terminal_keys.terminal_mode.enter` keymap.

### Commands

The plugin provides a single command with multiple sub-commands:

```vim
:CLIIntegration [subcommand]
```

**Available sub-commands:**

- `:CLIIntegration open_cwd` - Open in current file's directory
- `:CLIIntegration open_root` - Open in project root (git root)

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
2. Configure `integrations` with your CLI tool(s) (e.g., `integrations = { { cli_cmd = "cursor-agent" } }`)
3. Make sure your CLI tool(s) are installed and available in your `$PATH`
4. Open Neovim and press `<leader>aj` to open your CLI tool (uses first integration by default)
5. Type your command or question
6. Press `<C-s>` or `<CR><CR>` to submit
7. Use `<C-p>` to quickly attach files to the conversation

### Multiple Integrations Example

```lua
require("cli-integration").setup({
  integrations = {
    { cli_cmd = "cursor-agent" },
    { cli_cmd = "claude", window_width = 80 },
  },
})
```

This allows you to use both `cursor-agent` and `claude` simultaneously, each with its own terminal and configuration.

## 💡 Tips

- **Attach Multiple Files**: Use `<C-p><C-p>` to quickly attach all your open buffers
- **Quick Submit**: Double-tap `<CR>` or use `<C-s>` to submit without leaving insert mode
- **Context Switching**: Use `:CLIIntegration open_cwd` vs `:CLIIntegration open_root`
  depending on whether you want file-level or project-level context
- **Help Anytime**: Press `??` in terminal mode to see all available keymaps (shows config for current integration)
- **Multiple Tools**: Configure multiple CLI tools and switch between them. Each maintains its own terminal and settings.
- **Global Defaults**: Set common settings once at the global level, then override per-integration as needed.
- **Configuration Help**: If you forget to configure `integrations` or `cli_cmd`, the plugin will show you
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
