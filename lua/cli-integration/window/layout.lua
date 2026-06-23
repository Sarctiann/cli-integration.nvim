--- @module 'cli-integration.window.layout'
local M = {}
local state = require("cli-integration.window.state")
local geometry = require("cli-integration.window.geometry")
local debug = require("cli-integration.debug")
local config = require("cli-integration.config")

--- Apply sidebar window options to a vsplit window
--- @param win number Window handle
--- @param padding number Horizontal padding (foldcolumn)
local function apply_sidebar_win_opts(win, padding)
    vim.wo[win].winfixwidth = config.options.window_features and config.options.window_features.dynamic_resize == false
    vim.wo[win].winfixheight = true
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].cursorline = false
    vim.wo[win].spell = false
    vim.wo[win].winhighlight = "Normal:NormalSB,NormalNC:NormalSB,EndOfBuffer:NormalSB"
    if padding > 0 then
        vim.wo[win].foldcolumn = tostring(padding)
    end
end

--- Find a safe anchor window in the normal layout for creating splits
--- @return number|nil
function M.find_layout_anchor_window()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if state.is_valid_win(win) and not state.is_any_integration_win(win) then
            local cfg = vim.api.nvim_win_get_config(win)
            if cfg.relative == "" then
                local buf = vim.api.nvim_win_get_buf(win)
                local bt = vim.bo[buf].buftype
                if bt == "" then
                    return win
                end
            end
        end
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if state.is_valid_win(win) and not state.is_any_integration_win(win) then
            local cfg = vim.api.nvim_win_get_config(win)
            if cfg.relative == "" then
                return win
            end
        end
    end
    return nil
end

--- Create a centered floating window
--- @param buf number Terminal buffer
--- @param win_opts table Window options
--- @return number|nil The floating window handle
function M.create_float_window(buf, win_opts)
    local width = win_opts.width or math.floor(vim.o.columns * 0.8)
    local height = win_opts.height or math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local float_opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = win_opts.border or "rounded",
        title = win_opts.title or "",
        title_pos = "center",
    }

    local win = vim.api.nvim_open_win(buf, true, float_opts)
    debug.log("create_float_window", function()
        return { buf = buf, win = win, width = width, height = height }
    end)

    state.sidebars[buf] = {
        term_buf = buf,
        mode = "float",
        origin = "float",
        sidebar_win = nil,
        float_win = win,
        float_original = { width = width, height = height, row = row, col = col },
        fullscreen_autocmd_id = nil,
        width_config = width,
        win_opts = win_opts,
        padding = 0,
        list_buffer = win_opts.list_buffer or false,
        _last_pty_width = -1,
        _last_pty_height = -1,
    }

    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(win),
        callback = function()
            debug.log("autocmd_float_win_closed", function()
                return { term_buf = buf, closed_win = win }
            end)
            state.sidebars[buf] = nil
        end,
        once = true,
        desc = "Cleanup float-origin entry on close",
    })

    vim.api.nvim_create_autocmd("WinLeave", {
        buffer = buf,
        callback = function()
            debug.log("autocmd_term_win_leave", function()
                return { term_buf = buf, left_win = vim.api.nvim_get_current_win() }
            end)
            vim.schedule(function()
                vim.cmd("stopinsert")
            end)
        end,
        desc = "Exit insert mode when leaving terminal window",
    })

    vim.cmd("startinsert")
    return win
end

--- Create the Sidebar layout (vsplit terminal on right side)
--- @param buf number Terminal buffer
--- @param win_opts table Window options
--- @return number|nil The vsplit window handle
function M.create_sidebar_layout(buf, win_opts)
    local width_config = win_opts.min_width or win_opts.width or 34
    local padding = win_opts.padding or 0
    local configured_width = geometry.calculate_width(width_config)

    local anchor_win = M.find_layout_anchor_window()
    if anchor_win and vim.api.nvim_win_is_valid(anchor_win) then
        pcall(vim.api.nvim_set_current_win, anchor_win)
    end
    vim.cmd("botright vsplit")
    local sidebar_win = vim.api.nvim_get_current_win()

    vim.api.nvim_win_set_buf(sidebar_win, buf)
    vim.bo[buf].filetype = "cli-integration"

    local existing = state.sidebars[buf] --- @type Cli-Integration.SidebarEntry
    if existing then
        existing.sidebar_win = sidebar_win
        existing.mode = "sidebar"
        existing.float_win = nil
        existing.float_original = nil
        existing.fullscreen_autocmd_id = nil
        existing._pty_resize_pending = false
    else
        state.sidebars[buf] = {
            term_buf = buf,
            mode = "sidebar",
            origin = "sidebar",
            sidebar_win = sidebar_win,
            float_win = nil,
            float_original = nil,
            fullscreen_autocmd_id = nil,
            width_config = width_config,
            win_opts = win_opts,
            padding = padding,
            list_buffer = win_opts.list_buffer or false,
            _pty_resize_pending = false,
            _last_pty_width = -1,
            _last_pty_height = -1,
        }
    end

    M.apply_geometry(buf)
    apply_sidebar_win_opts(sidebar_win, padding)

    if config.options.adapters and config.options.adapters.bufferline then
        require("adapters.bufline").inject_offset(buf, win_opts.title or "")
    end

    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(sidebar_win),
        callback = function()
            debug.log("autocmd_sidebar_win_closed", function()
                return { term_buf = buf, sidebar_win = sidebar_win, mode = existing and existing.mode or "new" }
            end)
            local data = state.sidebars[buf]
            if data then
                data.sidebar_win = nil
            end
        end,
        once = true,
        desc = "Clear sidebar reference on vsplit close",
    })

    vim.cmd("startinsert")
    debug.log("create_sidebar_layout", function()
        local raw_w = vim.api.nvim_win_get_width(sidebar_win)
        local raw_h = vim.api.nvim_win_get_height(sidebar_win)
        return {
            buf = buf,
            sidebar_win = sidebar_win,
            padding = padding,
            win_width = raw_w,
            win_height = raw_h,
            configured_width = configured_width,
            editor_columns = vim.o.columns,
            editor_lines = vim.o.lines,
            cmdheight = vim.o.cmdheight,
            laststatus = vim.o.laststatus,
            showtabline = vim.o.showtabline,
        }
    end)
    return sidebar_win
end

--- Apply geometry and resize PTY
--- @param term_buf number
function M.apply_geometry(term_buf)
    local data = state.sidebars[term_buf]
    if not data then
        return
    end
    local geom = geometry.get_geometry(data)

    if data.mode == "sidebar" and state.is_valid_win(data.sidebar_win) then
        pcall(vim.api.nvim_win_set_width, data.sidebar_win, geom.width)
        geometry.resize_pty(term_buf, data.sidebar_win, data.padding or 0)
        local cw = vim.api.nvim_win_get_width(data.sidebar_win)
        local ch = vim.api.nvim_win_get_height(data.sidebar_win)
        data._last_pty_width = cw
        data._last_pty_height = ch
    elseif data.float_win and state.is_valid_win(data.float_win) then
        pcall(vim.api.nvim_win_set_config, data.float_win, geom)
        geometry.resize_pty(term_buf, data.float_win, 0)
        local cw = vim.api.nvim_win_get_width(data.float_win)
        local ch = vim.api.nvim_win_get_height(data.float_win)
        data._last_pty_width = cw
        data._last_pty_height = ch
    end
end

return M
