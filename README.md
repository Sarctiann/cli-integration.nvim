# 🔧 cli-integration.nvim

A Neovim plugin that seamlessly integrates any command-line tool into your Neovim workflow, providing an interactive terminal interface for CLI tools directly within your editor.

> **Note**: This plugin is a generic wrapper/integration tool for any CLI application.
> You need to configure the CLI command you want to use via the `cli_cmd` option.

## ✨ Features

- 🚀 **Quick Access**: Open CLI tool terminal with simple keymaps
- 📁 **Smart Context**: Automatically attach current file or project root
- 🔄 **Multiple Modes**: Work in current directory, project root, or custom paths
- 📋 **Buffer Management**: Easily attach single or multiple open buffers
- ⚡ **Interactive Terminal**: Full terminal integration with custom keymaps
- 🎯 **Flexible Configuration**: Configure any CLI tool through simple settings
- 💡 **Helpful Guidance**: Shows configuration help if CLI command is not set

## 📋 Requirements

- Neovim >= 0.9.0
- A CLI tool installed and available in your `$PATH` (configured via `cli_cmd`)
- [snacks.nvim](https://github.com/folke/snacks.nvim) (for terminal and notifications)

> **NOTE**: This plugin depends on [Snacks.nvim](https://github.com/folke/snacks.nvim)
> for terminal management and notifications.

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
--- @module 'cli-integration'
{
  "Sarctiann/cli-integration.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  --- @type cli-integration.Config
  opts = {
    cli_cmd = "your-cli-tool",  -- Required: specify your CLI command
    -- Configure your other options here
  },
}
```

### For local development

```lua
--- @module 'cli-integration'
{
  dir = "~/.config/nvim/lua/custom_plugins/cli-integration.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  --- @type cli-integration.Config
  opts = {
    cli_cmd = "your-cli-tool",  -- Required: specify your CLI command
    -- Configure your other options here
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
      cli_cmd = "your-cli-tool",  -- Required: specify your CLI command
      -- Configure your other options here
    })
  end
}
```

## ⚙️ Configuration

### Minimum Required Configuration

The only required option is `cli_cmd`, which specifies the CLI command to use:

```lua
require("cli-integration").setup({
  cli_cmd = "cursor-agent",  -- Required: your CLI command name
})
```

> **Important**: If `cli_cmd` is not configured, the plugin will display a helpful message
> indicating the minimum configuration required when you try to open the terminal.

### Default Configuration

```lua
-- These are the default values; you can use `setup({})` to use defaults
require("cli-integration").setup({
  cli_cmd = nil,  -- Required: specify your CLI command (e.g., "cursor-agent", "claude", etc.)
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

### Configuration Options

| Option              | Type      | Default   | Description                                                          |
| ------------------- | --------- | --------- | -------------------------------------------------------------------- |
| `cli_cmd`           | `string`  | `nil`     | **Required**: CLI command name to execute (e.g., "cursor-agent")     |
| `show_help_on_open` | `boolean` | `true`    | Show help screen when terminal opens                                 |
| `new_lines_amount`  | `number`  | `2`       | Number of new lines to insert after command submission               |
| `window_width`      | `number`  | `64`      | Default width for the terminal window                                |
| `terminal_keys`     | `table`   | See below | Key mappings for the CLI terminal window (all values must be arrays) |

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
  cli_cmd = "my-cli-tool",
  terminal_keys = {
    terminal_mode = {
      submit = { "<C-s>", "<C-Enter>" },  -- Multiple keys for submit
      help = { "??", "F1" },              -- Custom help keys
      toggle_width = { "<C-f>", "<C-w>" }, -- Multiple toggle options
    },
    normal_mode = {
      hide = { "<Esc>", "q" },            -- Multiple hide options
    },
  },
})
```

### Example Configurations

#### Cursor Agent

```lua
require("cli-integration").setup({
  cli_cmd = "cursor-agent",
})
```

#### Claude CLI

```lua
require("cli-integration").setup({
  cli_cmd = "claude",
  window_width = 80,
})
```

#### Custom CLI Tool

```lua
require("cli-integration").setup({
  cli_cmd = "my-custom-tool",
})
```

## 🎮 Usage

### Important Notes

- **⚠️ The main commands are `:CLIIntegration open_cwd`, `:CLIIntegration open_root`, and `:CLIIntegration session_list`.
  Each of these will open its own terminal (`win` and `buf`) or toggle to it if it's already open** This is handled by [Snacks.nvim](https://github.com/folke/snacks.nvim)'s `terminal()`.
- **Configuration Required**: If `cli_cmd` is not set, opening the terminal will display a helpful message
  showing the minimum configuration needed.
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
2. Configure `cli_cmd` with your CLI tool name (e.g., `cli_cmd = "cursor-agent"`)
3. Make sure your CLI tool is installed and available in your `$PATH`
4. Open Neovim and press `<leader>aj` to open your CLI tool
5. Type your command or question
6. Press `<C-s>` or `<CR><CR>` to submit
7. Use `<C-p>` to quickly attach files to the conversation

## 💡 Tips

- **Attach Multiple Files**: Use `<C-p><C-p>` to quickly attach all your open buffers
- **Quick Submit**: Double-tap `<CR>` or use `<C-s>` to submit without leaving insert mode
- **Context Switching**: Use `:CLIIntegration open_cwd` vs `:CLIIntegration open_root`
  depending on whether you want file-level or project-level context
- **Help Anytime**: Press `??` in terminal mode to see all available keymaps
- **Configuration Help**: If you forget to configure `cli_cmd`, the plugin will show you
  the minimum configuration needed when you try to open the terminal

## 🏗️ Project Structure

```bash
cli-integration.nvim/
└── lua/
    └── cli-integration/
        ├── init.lua          # Main entry point and setup
        ├── config.lua        # Configuration management
        ├── terminal.lua      # Terminal singleton management
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
