# Module Spec: dbg_print (commands.lua)

## Overview

Diagnostic subcommand for the `:CLIIntegration` user command. Prints window geometry,
sidebar state, and terminal job info to help debug resize and layout issues.

## Usage

```
:CLIIntegration dbg_print
```

## Output Sections

### Editor

Global editor dimensions and relevant options:

- `columns` — `vim.o.columns`
- `lines` — `vim.o.lines`
- `showtabline` — `vim.o.showtabline` (0=never, 1=multi, 2=always)
- `laststatus` — `vim.o.laststatus`
- `cmdheight` — `vim.o.cmdheight`

### Sidebars

One row per entry in `state.sidebars` (keyed by terminal buffer):

| Field | Source |
|-------|--------|
| `buf` | Buffer handle |
| `mode` | `data.mode` (sidebar, float, fullscreen) |
| `origin` | `data.origin` (sidebar, float) |
| `sidebar_win` | `data.sidebar_win` or `"nil"` |
| `float_win` | `data.float_win` or `"nil"` |
| `w` / `h` | Window dimensions (from the active win, or `"?"` if none) |
| `padding` | `data.padding` |
| `ft` | `vim.bo[buf].filetype` |
| `winfixwidth` | `vim.wo[win].winfixwidth` |
| `winfixheight` | `vim.wo[win].winfixheight` |

### Terminals

One row per entry in `M.terminals` (keyed by integration name):

| Field | Source |
|-------|--------|
| `name` | Integration name |
| `buf` | `term_buf` or `"?"` |
| `job` | `vim.bo[buf].channel` or `"?"` |
| `is_fullscreen` | `td.is_fullscreen` |

## Source Location

`M.dbg_print()` in `lua/cli-integration/commands.lua` (~55 lines)
