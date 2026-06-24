# Module Spec: init.lua

## Overview

Plugin entry point and user command registration.

## Responsibility

- Initializes plugin configuration
- Creates the `:CLIIntegration` and `:CIcmd` user commands
- Handles visual selection range for passing text to CLI tools
- Normalizes integration names (underscores ↔ spaces) for autocompletion compatibility
- Validates integrations exist before executing commands

## Public API

### `M.setup(user_config)`

**Signature:** `function M.setup(user_config: Cli-Integration.Config): nil`

**Flow:**

1. Calls `config.setup(user_config)` to validate and merge configuration
2. Creates user command `:CLIIntegration` with autocompletion
3. Sets up autocommands via `autocmds.setup(configs)`

**Command Logic (`:CLIIntegration`):**

- Validates integrations are configured (non-empty)
- Parses arguments: action → integration_name → cli_args
- Converts underscores back to spaces in integration name (for autocompletion compatibility)
- Captures visual selection if range is provided (`opts.range > 0`)
- Routes to `commands.open_cwd()`, `commands.open_git_root()`, or `commands.dbg_print()`
- Supports backward compatibility: first arg not a known action → treated as integration name

## Command Autocompletion

The `:CLIIntegration` command supports tab autocompletion:

- First argument: shows `open_cwd`, `open_root`, `dbg_print`
- Second argument: shows integration names (spaces converted to underscores)

## Exposed Hooks

- `M.hooks` — table containing all hooks from `hooks.lua`
- `M.hooks.ask` — exposed for easy access via `require("cli-integration").hooks.ask("IntegrationName")`

## Dependencies

- `config.lua` — configuration management
- `commands.lua` — command execution
- `autocmds.lua` — autocommand setup
- `ask.lua` — ask hook
- `hooks.lua` — shared hooks

## Key Implementation Details

- Integration names use underscores for autocompletion display but spaces internally
- Visual selection is captured as lines from `nvim_buf_get_lines()` and concatenated with newlines
- All command execution is wrapped in `pcall()` with error notifications

## Source Location

`lua/cli-integration/init.lua` (148 lines)
