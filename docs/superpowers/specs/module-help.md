# Module Spec: help.lua

## Overview

Help text generation and display.

## Public API

### `M.show_help()`

Shows full help notification with all keymaps and CLI commands.

**Sections:**

- "Term Mode" — Terminal mode keymaps
- "Norm Mode" — Normal mode keymaps
- `<cli_cmd> commands` — Generic CLI commands (quit/exit, /, @, !)

### `M.show_quick_help()`

Shows brief help notification with help key combinations.

Displayed on terminal open if `show_help_on_open` is enabled.

## Helper Functions

### `generate_help_text()`

Generates formatted help text from configuration.

**Process:**

1. Get integration for current terminal buffer
2. Get terminal keys (integration-specific or global defaults)
3. Build aligned table with key -> description mapping

### `format_keys(keys)`

Joins array of keys with " | " separator.

### `format_help_line(keys, description, key_width)`

Formats line with alignment:

```
    - <key>    : <description>
```

### `get_max_key_width(entries)`

Calculates max width for key alignment.

## Source Location

`lua/cli-integration/help.lua` (174 lines)
