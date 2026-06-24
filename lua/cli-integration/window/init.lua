--- @module 'cli-integration.window'
local M = {}
local state = require("cli-integration.window.state")
local geometry = require("cli-integration.window.geometry")
local layout = require("cli-integration.window.layout")
local dynamic_resize = require("cli-integration.window.features.dynamic_resize")
local fullscreen = require("cli-integration.window.features.fullscreen")
local buffer_lock = require("cli-integration.window.features.buffer_lock")
local insert = require("cli-integration.window.features.insert")
local nav = require("cli-integration.window.features.nav")
local debug = require("cli-integration.debug")
local config = require("cli-integration.config")

M.sidebars = state.sidebars

--- @class TerminalWindow
--- @field buf number
--- @field win number
--- @field job_id number
--- @field cmd string
--- @field opts table
--- @field on_close (fun()|nil)
--- @field toggle fun()

--- Create a new terminal window
--- @param cmd string Command to run in terminal
--- @param opts table Options for terminal creation
--- @return TerminalWindow|nil
function M.create_terminal(cmd, opts)
    opts = opts or {}
    local win_opts = opts.win or {}
    local cwd = opts.cwd or vim.fn.getcwd()
    local auto_close = opts.auto_close ~= false

    local buf = vim.api.nvim_create_buf(false, true)
    if not buf or buf == 0 then
        return nil
    end

    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].buflisted = false

    if win_opts.integration_name and win_opts.integration_name ~= "" then
        vim.api.nvim_buf_set_var(buf, "cli_integration_name", win_opts.integration_name)
    end

    local is_float = win_opts.position == "float"
    local win

    if is_float then
        win = layout.create_float_window(buf, win_opts)
    else
        win = layout.create_sidebar_layout(buf, win_opts)
    end

    if not win then
        vim.api.nvim_buf_delete(buf, { force = true })
        return nil
    end

    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].spell = false
    vim.wo[win].cursorline = false

    local terminal = {
        buf = buf,
        win = win,
        job_id = 0,
        cmd = cmd,
        opts = opts,
        on_close = win_opts.on_close,
    }

    terminal.toggle = function()
        M.toggle_terminal(terminal)
    end
    local integration_name = win_opts.integration_name or ""

    local padding = is_float and 0 or (win_opts.padding or 0)
    local cols, lines = geometry.calculate_content_dimensions(win, padding)

    local job_id
    vim.api.nvim_buf_call(buf, function()
        local original_cwd = vim.fn.getcwd()
        if cwd and cwd ~= "" then
            vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
        end

        local env = geometry.build_job_env(opts, cols, lines)
        debug.log("create_terminal", function()
            local raw_w = vim.api.nvim_win_get_width(win)
            local raw_h = vim.api.nvim_win_get_height(win)
            return {
                cmd = cmd,
                buf = buf,
                integration_name = integration_name,
                is_float = is_float,
                padding = padding,
                win_width = raw_w,
                win_height = raw_h,
                content_width = cols,
                content_height = lines,
                border = win_opts.border or "none",
            }
        end)

        local use_jobstart = vim.fn.has("nvim-0.11") == 1
        local job_opts = {
            cwd = cwd,
            env = env,
            term = true,
            on_exit = function(_, exit_code, _)
                if auto_close and exit_code == 0 then
                    vim.schedule(function()
                        local title = (win_opts.title ~= "" and win_opts.title) or "cli"
                        local msg = "... bye bye" .. title .. " "
                        local notif_buf = vim.api.nvim_create_buf(false, true)
                        vim.api.nvim_buf_set_lines(notif_buf, 0, -1, false, { msg })
                        local width = #msg
                        local notif_win = vim.api.nvim_open_win(notif_buf, false, {
                            relative = "editor",
                            width = width,
                            height = 1,
                            row = vim.o.lines - 4,
                            col = vim.o.columns - width - 2,
                            style = "minimal",
                            border = "rounded",
                            focusable = false,
                        })
                        vim.defer_fn(function()
                            pcall(vim.api.nvim_win_close, notif_win, true)
                            pcall(vim.api.nvim_buf_delete, notif_buf, { force = true })
                        end, 1000)
                    end)
                    vim.defer_fn(function()
                        if vim.api.nvim_buf_is_valid(buf) then
                            vim.api.nvim_buf_delete(buf, { force = true })
                        end
                    end, 1000)
                end
                if win_opts.on_close then
                    vim.schedule(win_opts.on_close)
                end
            end,
        }

        if use_jobstart then
            job_id = vim.fn.jobstart(cmd, job_opts)
        else
            job_opts.term = nil
            ---@diagnostic disable-next-line: deprecated
            job_id = vim.fn.termopen(cmd, job_opts)
        end

        vim.cmd("lcd " .. vim.fn.fnameescape(original_cwd))
    end)

    if padding > 0 then
        vim.wo[win].foldcolumn = tostring(padding)
    end

    if not job_id or job_id <= 0 then
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
        return nil
    end

    terminal.job_id = job_id

    -- apply_geometry (called inside create_sidebar_layout) also calls
    -- resize_pty, but that runs *before* the terminal job exists so the
    -- channel is 0 and the call is a no-op.  Always call it here after the
    -- job is created so the PTY starts with the correct dimensions.
    geometry.resize_pty(buf, win, padding)
    local data_entry = state.sidebars[buf]
    if data_entry then
        data_entry._last_pty_width = vim.api.nvim_win_get_width(win)
        data_entry._last_pty_height = vim.api.nvim_win_get_height(win)
        data_entry._last_win_width = vim.api.nvim_win_get_width(win)
        data_entry._last_win_height = vim.api.nvim_win_get_height(win)
    end

    if opts.win and opts.win.list_buffer then
        vim.bo[buf].buflisted = true
    end

    if win_opts.buffer_name and win_opts.buffer_name ~= "" then
        pcall(vim.api.nvim_buf_set_name, buf, win_opts.buffer_name)
    end

    nav.setup(buf)
    insert.setup(buf, win_opts)
    buffer_lock.setup(buf)
    dynamic_resize.setup()
    fullscreen.setup()

    return terminal
end

--- Toggle terminal window visibility
--- @param terminal TerminalWindow
function M.toggle_terminal(terminal)
    if not terminal or not terminal.buf or not vim.api.nvim_buf_is_valid(terminal.buf) then
        return
    end

    local data = state.sidebars[terminal.buf]

    if data then
        local win = data.sidebar_win or data.float_win
        if win and state.is_valid_win(win) then
            vim.api.nvim_win_close(win, false)
            terminal.win = nil
        else
            local win_opts = terminal.opts.win or {}
            local new_win

            if win_opts.position == "float" then
                new_win = layout.create_float_window(terminal.buf, win_opts)
            else
                new_win = layout.create_sidebar_layout(terminal.buf, win_opts)
            end

            if new_win then
                terminal.win = new_win
            end
        end
    else
        local current_win = nil
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(w) == terminal.buf then
                current_win = w
                break
            end
        end

        if current_win and vim.api.nvim_win_is_valid(current_win) then
            vim.api.nvim_win_close(current_win, false)
            terminal.win = nil
        else
            local win_opts = terminal.opts.win or {}
            local new_win

            if win_opts.position == "float" then
                new_win = layout.create_float_window(terminal.buf, win_opts)
            else
                new_win = layout.create_sidebar_layout(terminal.buf, win_opts)
            end

            if new_win then
                terminal.win = new_win
            end
        end
    end
end

--- Check if a terminal window is visible
--- @param terminal TerminalWindow
--- @return boolean
function M.is_terminal_visible(terminal)
    if not terminal or not terminal.buf or not vim.api.nvim_buf_is_valid(terminal.buf) then
        return false
    end
    local data = state.sidebars[terminal.buf]
    if not data then
        return false
    end
    return ((data.sidebar_win and state.is_valid_win(data.sidebar_win)) or (data.float_win and state.is_valid_win(data.float_win))) == true
end

--- Public wrapper for resize_pty
--- @param term_buf number
--- @param win number
--- @param padding number
function M.resize_pty(term_buf, win, padding)
    geometry.resize_pty(term_buf, win, padding)
end

M.update_sidebar_geometry = fullscreen.update_sidebar_geometry
M.update_float_geometry = fullscreen.update_float_geometry
M.set_nav_keymaps_enabled = nav.set_nav_keymaps_enabled
M.apply_geometry = layout.apply_geometry

M.resize_sidebars = function()
    dynamic_resize.resize_sidebars()
end

local _buf_autocmd_setup = false
local _deferred_resize_pending = false
local function resize_all_sidebars()
    if vim.tbl_count(state.sidebars) == 0 then
        if config.options and config.options.adapters and config.options.adapters.bufferline then
            require("adapters.bufline").restore()
        end
        return
    end
    for _, data in pairs(state.sidebars) do
        local win = data.sidebar_win or data.float_win
        if win and state.is_valid_win(win) then
            if data.mode == "sidebar" then
                local expected_width = geometry.calculate_width(data.width_config)
                local current_width = vim.api.nvim_win_get_width(win)
                if current_width ~= expected_width then
                    pcall(vim.api.nvim_win_set_width, win, expected_width)
                end
            end
            geometry.resize_pty(data.term_buf, win, data.padding or 0)
        end
    end
    if config.options and config.options.adapters and config.options.adapters.bufferline then
        local has_active = false
        for _, data in pairs(state.sidebars) do
            local win = data.sidebar_win or data.float_win
            if win and state.is_valid_win(win) then
                has_active = true
                break
            end
        end
        if has_active then
            local bufline = require("adapters.bufline")
            for buf, data in pairs(state.sidebars) do
                bufline.inject_offset(buf, (data.win_opts and data.win_opts.title) or "")
            end
        else
            require("adapters.bufline").restore()
        end
    end
end

--- When the bufferline adapter is active, pin showtabline=2 while any
--- integration window is visible so the sidebar height stays stable.
--- bufferline (or Neovim itself) may try to change showtabline when buffers
--- open/close — this guard reverts it immediately.
local function ensure_showtabline_while_active()
    if not config.options or not config.options.adapters or not config.options.adapters.bufferline then
        return false
    end
    for _, d in pairs(state.sidebars) do
        if state.is_valid_win(d.sidebar_win) or state.is_valid_win(d.float_win) then
            if vim.o.showtabline ~= 2 then
                vim.o.showtabline = 2
            end
            return true
        end
    end
    return false
end

vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "showtabline",
    callback = function()
        if vim.o.showtabline ~= 2 then
            ensure_showtabline_while_active()
        end
    end,
    desc = "Pin showtabline to 2 while bufferline adapter is active and sidebar visible",
})

--- Deferred resize: after a buffer opens/closes, wait 50ms for the layout
--- to settle (showtabline transition, window redistribution) before restoring
--- sidebar width and sending SIGWINCH.  This handles the case where
--- showtabline isn't pinned (adapter disabled) and the sidebar shifts.
local function deferred_resize()
    if _deferred_resize_pending then
        return
    end
    _deferred_resize_pending = true
    vim.defer_fn(function()
        _deferred_resize_pending = false
        resize_all_sidebars()
    end, 50)
end

local function ensure_buf_autocmd()
    if _buf_autocmd_setup then
        return
    end
    _buf_autocmd_setup = true
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufDelete" }, {
        callback = function()
            deferred_resize()
        end,
        desc = "Deferred resize of sidebar on file open/close",
    })
end

ensure_buf_autocmd()

return M
