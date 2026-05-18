# Spec: `ask` Hook for cli-integration.nvim

**Date:** 2026-05-17
**Status:** Approved
**Context:** Neovim + cli-integration.nvim plugin

---

## 1. Problem Statement

The `cli-integration.nvim` plugin embeds CLI TUIs (OpenCode, Gemini, Augment) inside Neovim as sidebar/floating terminals. Currently, the only way to send context (file paths, selected code) to these integrations is through the `start_with_text` mechanism, which:

1. Only fires when the integration is **first opened** (not during an active session).
2. Hardcodes the prompt: "Explain this code:\n`\n<selection>\n`".
3. Does not allow the user to type a **custom question**.

Users want to:

- Select code in visual mode, press a keybinding, type a question in a floating input, and have both the selection and the question sent to the active integration.
- Do the same from normal mode (cursor line as context, no selection).
- Have this work generically for any configured integration (OpenCode, Gemini, Augment, etc.).

---

## 2. Design Overview

### 2.1 New Module: `ask.lua`

A new module `cli-integration/lua/cli-integration/ask.lua` implements the `ask` hook. It exposes a single public function:

```lua
M.ask(integration_identifier) → nil
```

### 2.2 Flow

```
User (n/v mode) → keybinding → hooks.ask("OpenCode")
  │
  ├─ 1. Capture context (file, lines, selection, filetype)
  │     - In visual mode: read '< and '> marks for range + content
  │     - In normal mode: cursor line only, selection = nil
  │
  ├─ 2. Look up integration by name in terminal.terminals
  │
  ├─ 3. Ensure terminal is ready:
  │     a. Hidden?     → toggle (show)
  │     b. Closed?     → open_terminal() + wait for CLI readiness
  │                       (suppress existing start_with_text)
  │
  ├─ 4. Show floating input window:
  │     - border: "rounded"
  │     - title: integration.ask_title || integration.name
  │     - position: cursor-relative (screenrow/screencol), clamped to viewport
  │     - dimensions: width = min(60, columns - 4), height = 3
  │     - keymaps: <CR> → submit, <Esc> → cancel
  │     - auto-enter insert mode
  │
  ├─ 5. User types question, presses <CR>
  │
  ├─ 6. Build AskData table:
  │     { file, relative_file, start_line, end_line, selection, question, filetype }
  │
  ├─ 7. Call integration.format_ask_query(data, integration) → formatted_string
  │     (fallback to default formatter if not configured)
  │
  ├─ 8. Send formatted_string to terminal via chansend(job_id, text)
  │
  ├─ 9. Send "\r" via chansend for auto-submit
  │
  └─ 10. Focus the integration window
```

### 2.3 The `AskData` Table

```lua
--- @class Cli-Integration.AskData
--- @field file string          Absolute path of the current file
--- @field relative_file string Path relative to the integration's workspace
--- @field start_line number    1-indexed start line (from selection or cursor)
--- @field end_line number      1-indexed end line (= start_line if no selection)
--- @field selection string|nil Selected text content (nil if no visual selection)
--- @field question string      The user's typed question
--- @field filetype string      vim.bo.filetype of the source buffer
```

---

## 3. Configuration Changes

### 3.1 New Integration Fields (`config.lua`)

| Field              | Type                                                   | Required | Default            | Description                                                            |
| ------------------ | ------------------------------------------------------ | -------- | ------------------ | ---------------------------------------------------------------------- |
| `format_ask_query` | `fun(data: AskData, integration: Integration): string` | No       | Built-in default   | Formats the AskData into a string that gets inserted into the terminal |
| `ask_title`        | `string`                                               | No       | `integration.name` | Custom title for the floating input window                             |

### 3.2 Public API Exposure (`init.lua`)

```lua
M.hooks.ask = require("cli-integration.ask").ask
```

### 3.3 Default Formatter

When `format_ask_query` is not configured:

````lua
function(data, integration)
  local parts = { data.question, "" }
  local fmt = integration.format_paths
  if data.selection then
    table.insert(parts, "```" .. data.relative_file .. ":"
      .. data.start_line .. "-" .. data.end_line)
    table.insert(parts, data.selection)
    table.insert(parts, "```")
  else
    local ref = data.relative_file .. ":" .. data.start_line
    table.insert(parts, (fmt and fmt(ref)) or ref)
  end
  return table.concat(parts, "\n")
end
````

### 3.4 User Config Example (`local_config.lua`)

````lua
-- In the OpenCode integration:
{
  name = "OpenCode",
  -- ... existing config ...
  ask_title = "Preguntar a OpenCode",  -- optional
  format_ask_query = function(data, integration)
    local parts = { data.question, "" }
    if data.selection then
      table.insert(parts, "```" .. data.relative_file .. ":"
        .. data.start_line .. "-" .. data.end_line)
      table.insert(parts, data.selection)
      table.insert(parts, "```")
    else
      table.insert(parts, "@" .. data.relative_file .. ":" .. data.start_line)
    end
    return table.concat(parts, "\n")
  end,
}

-- Keymap (works in normal and visual mode):
{
  "<leader>aq",
  function()
    require("cli-integration").hooks.ask("OpenCode")
  end,
  desc = "OpenCode Ask (inline)",
  mode = { "n", "v" },
}
````

---

## 4. Floating Input Window

### 4.1 Positioning Strategy

Use `screenrow()` and `screencol()` (captured **before** any window operations) to position the floating input near the cursor. Apply clamping to keep it within the editor bounds:

```lua
local screen_row = vim.fn.screenrow() - 1   -- 0-indexed
local screen_col = vim.fn.screencol() - 1   -- 0-indexed

local width = math.min(60, vim.o.columns - 4)
local height = 3

local row = screen_row + 1                    -- below cursor
local col = screen_col - math.floor(width / 2) -- centered on cursor

-- Clamp horizontal
col = math.max(0, math.min(col, vim.o.columns - width))

-- Clamp vertical: if off-screen at bottom, place above cursor
if row + height > vim.o.lines - 1 then
  row = screen_row - height - 1
  row = math.max(0, row)
end
```

### 4.2 Window Properties

- `relative = "editor"`, `style = "minimal"`
- `border = "rounded"` with `title` and `title_pos = "center"`
- Buffer: nofile, bufhidden=wipe
- Auto-enters insert mode (`startinsert!`)

### 4.3 Keymaps (buffer-local)

| Key                     | Action                                      |
| ----------------------- | ------------------------------------------- |
| `<CR>` (insert mode)    | Capture text, close window, invoke callback |
| `<Esc>` (insert/normal) | Close window, cancel                        |

### 5.0 Terminal Readiness: Handling `start_with_text` Collision

When the ask hook auto-opens a closed integration (via `terminal.open_terminal()`), the existing `start_with_text` mechanism would normally fire (via `attach_text_when_ready`). This is suppressed when initiated from the ask hook — the ask hook's formatted question takes priority. Implementation: pass a flag `skip_start_with_text = true` through the open flow.

---

## 5. Terminal Interaction

### 5.1 Ensuring Terminal Readiness

```lua
local function ensure_terminal_ready(integration, callback)
  local name = integration.name
  local term_data = terminal.terminals[name]

  if term_data and term_data.term_buf and vim.api.nvim_buf_is_valid(term_data.term_buf) then
    -- Terminal exists. If hidden, show it first.
    local term_win = find_window_for_buf(term_data.term_buf)
    if not term_win then
      -- Hidden. Toggle to show.
      term_data.cli_term:toggle()
    end
    callback(term_data)
  else
    -- Terminal doesn't exist. Open it and wait for readiness.
    terminal.open_terminal(integration, nil, integration.keep_open, get_working_dir())
    -- Wait for CLI readiness, then callback
    wait_for_terminal_and_proceed(integration, callback)
  end
end
```

### 5.2 Sending Text and Submitting

```lua
-- Send formatted text
terminal.insert_text(formatted_text, term_buf)

-- Auto-submit: send Enter
local job_id = vim.api.nvim_buf_get_var(term_buf, "terminal_job_id")
-- Note: vim.b.terminal_job_id is the new API (>0.11); try both
if job_id then
  vim.fn.chansend(job_id, "\r")
end

-- Focus the terminal window
focus_terminal_window(term_buf)
```

---

## 6. Error Handling

| Scenario                    | Behavior                                                                                                         |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Integration not found       | `vim.notify` error, return                                                                                       |
| No integrations configured  | `vim.notify` error, return                                                                                       |
| `format_ask_query` throws   | `pcall`-wrapped; `vim.notify` error, no text sent                                                                |
| Terminal job dead           | `vim.notify` warning, no text sent                                                                               |
| Empty question submitted    | Ignored, window closes silently                                                                                  |
| User presses `<Esc>`        | Window closes, no text sent                                                                                      |
| `start_with_text` collision | Suppressed: when ask hook auto-opens integration, the existing `start_with_text` is skipped (ask takes priority) |

---

## 7. Files Changed

| File                               | Change                                                                          |
| ---------------------------------- | ------------------------------------------------------------------------------- |
| `lua/cli-integration/ask.lua`      | **NEW** — ask hook implementation                                               |
| `lua/cli-integration/config.lua`   | Add `format_ask_query` and `ask_title` to schema + defaults                     |
| `lua/cli-integration/init.lua`     | Add `M.hooks.ask` exposure                                                      |
| `lua/cli-integration/terminal.lua` | Add helper: `find_terminal_window()`, `get_job_id()`, `focus_terminal_window()` |
| `local_config.lua` (user)          | Add `format_ask_query`, keymaps                                                 |

---

## 8. Testing Plan

1. **Normal mode, integration open**: `<leader>aq` → input appears → type question → Enter → text appears in terminal + auto-submits
2. **Visual mode, integration open**: select text → `<leader>aq` → input appears → type question → Enter → selection + question in terminal
3. **Integration hidden**: `<leader>aq` → integration becomes visible → input → submit
4. **Integration closed**: `<leader>aq` → integration opens → waits for readiness → input → submit
5. **Empty question**: type nothing → Enter → nothing sent, window closes
6. **Escape cancel**: type → Esc → nothing sent, window closes
7. **Multiple integrations**: `ask("Gemini")` → sends to Gemini, not OpenCode
8. **Custom formatter**: `format_ask_query` returns custom format → reflected in terminal output

---

## 9. Non-Goals

- Multi-line input (keeps single-line for simplicity)
- Persisted ask history
- Integration-agnostic HTTP API (stays on terminal channel)
- Replacing existing `start_with_text` behavior (complementary, not replacement)
