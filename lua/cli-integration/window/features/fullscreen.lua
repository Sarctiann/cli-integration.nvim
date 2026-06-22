--- @module 'cli-integration.window.features.fullscreen'
local M = {}
local state = require("cli-integration.window.state")
local geometry = require("cli-integration.window.geometry")
local layout = require("cli-integration.window.layout")
local debug = require("cli-integration.debug")
local config = require("cli-integration.config")

--- Update sidebar geometry (handles fullscreen toggle for sidebar-origin integrations)
--- @param term_buf number The terminal buffer (key into M.sidebars)
--- @param is_fullscreen boolean Whether to show in fullscreen mode
--- @param should_focus boolean|nil Whether to focus the window (default: false)
function M.update_sidebar_geometry(term_buf, is_fullscreen, should_focus)
    local data = state.sidebars[term_buf]
    if not data or data.origin ~= "sidebar" then
        return
    end
    local from_mode = data.mode

    if is_fullscreen then
        debug.log("update_sidebar_geometry", function()
            return {
                term_buf = term_buf,
                from_mode = from_mode,
                to_mode = "fullscreen",
                sidebar_win = data.sidebar_win,
                float_win = data.float_win,
                border = "single",
                height_formula = tostring(vim.o.lines) .. "-" .. tostring(vim.o.cmdheight) .. "-3=" .. tostring(
                    vim.o.lines - vim.o.cmdheight - 3
                ),
                width = vim.o.columns,
                editor_lines = vim.o.lines,
                editor_columns = vim.o.columns,
                cmdheight = vim.o.cmdheight,
            }
        end)
        if data.sidebar_win and state.is_valid_win(data.sidebar_win) then
            pcall(vim.api.nvim_win_set_width, data.sidebar_win, 1)
        end

        local float_opts = {
            relative = "editor",
            width = vim.o.columns,
            height = vim.o.lines - vim.o.cmdheight - 3,
            row = 0,
            col = 0,
            style = "minimal",
            border = "single",
            title = data.win_opts.title or "",
            title_pos = "center",
        }

        local new_win = vim.api.nvim_open_win(data.term_buf, true, float_opts)

        if new_win then
            vim.wo[new_win].number = false
            vim.wo[new_win].relativenumber = false
            vim.wo[new_win].signcolumn = "no"
            vim.wo[new_win].spell = false
            vim.wo[new_win].cursorline = false

            data.float_win = new_win
            data.mode = "fullscreen"

            local autocmd_id = vim.api.nvim_create_autocmd("WinClosed", {
                pattern = tostring(new_win),
                callback = function()
                    state.sidebars[term_buf] = nil
                end,
                once = true,
                desc = "Cleanup fullscreen float on close",
            })
            data.fullscreen_autocmd_id = autocmd_id

            geometry.resize_pty(data.term_buf, new_win, 0)
            data._last_win_width = vim.api.nvim_win_get_width(new_win)
            data._last_win_height = vim.api.nvim_win_get_height(new_win)
            data._last_pty_width = data._last_win_width
            data._last_pty_height = data._last_win_height
            debug.log("fullscreen_float_created", function()
                return {
                    term_buf = term_buf,
                    new_win = new_win,
                    win_width = vim.api.nvim_win_get_width(new_win),
                    win_height = vim.api.nvim_win_get_height(new_win),
                    border = "single",
                    padding = 0,
                    mode = "fullscreen",
                }
            end)

            if should_focus then
                vim.api.nvim_set_current_win(new_win)
                vim.schedule(function()
                    if state.is_valid_win(new_win) then
                        vim.cmd("startinsert")
                    end
                end)
            end
        end
    else
        debug.log("update_sidebar_geometry", function()
            local restored_sidebar_win = data.sidebar_win
            local w = restored_sidebar_win
                    and state.is_valid_win(restored_sidebar_win)
                    and vim.api.nvim_win_get_width(restored_sidebar_win)
                or -1
            local h = restored_sidebar_win
                    and state.is_valid_win(restored_sidebar_win)
                    and vim.api.nvim_win_get_height(restored_sidebar_win)
                or -1
            return {
                term_buf = term_buf,
                from_mode = from_mode,
                to_mode = "sidebar",
                sidebar_win = data.sidebar_win,
                float_win = data.float_win,
                win_width = w,
                win_height = h,
                padding = data.padding or 0,
                editor_lines = vim.o.lines,
                editor_columns = vim.o.columns,
            }
        end)
        local float_win = data.float_win

        if data.fullscreen_autocmd_id then
            pcall(vim.api.nvim_del_autocmd, data.fullscreen_autocmd_id)
            data.fullscreen_autocmd_id = nil
        end

        if float_win and state.is_valid_win(float_win) then
            pcall(vim.api.nvim_win_close, float_win, true)
            data.float_win = nil
        end

        local sidebar_win = data.sidebar_win
        if sidebar_win and state.is_valid_win(sidebar_win) then
            local configured_width = geometry.calculate_width(data.width_config)
            pcall(vim.api.nvim_win_set_width, sidebar_win, configured_width)
        else
            local fallback_win = layout.create_sidebar_layout(data.term_buf, data.win_opts)
            if fallback_win then
                data.sidebar_win = fallback_win
            end
        end

        sidebar_win = data.sidebar_win
        if sidebar_win and state.is_valid_win(sidebar_win) then
            geometry.resize_pty(data.term_buf, sidebar_win, data.padding or 0)
            data._last_win_width = vim.api.nvim_win_get_width(sidebar_win)
            data._last_win_height = vim.api.nvim_win_get_height(sidebar_win)
            data._last_pty_width = data._last_win_width
            data._last_pty_height = data._last_win_height
            if should_focus then
                vim.api.nvim_set_current_win(sidebar_win)
                vim.schedule(function()
                    if state.is_valid_win(sidebar_win) then
                        vim.cmd("startinsert")
                    end
                end)
            end
        end
    end
end

--- Update float geometry (handles fullscreen toggle for float-origin integrations)
--- @param term_buf number The terminal buffer
--- @param is_fullscreen boolean Whether to show in fullscreen mode
--- @param should_focus boolean|nil Whether to focus the window (default: false)
function M.update_float_geometry(term_buf, is_fullscreen, should_focus)
    local data = state.sidebars[term_buf]
    if not data or data.origin ~= "float" then
        return
    end

    local float_win = data.float_win
    if not float_win or not state.is_valid_win(float_win) then
        return
    end
    local original_mode = data.mode

    if is_fullscreen then
        local cfg = vim.api.nvim_win_get_config(float_win)
        data.float_original = {
            width = cfg.width,
            height = cfg.height,
            row = cfg.row,
            col = cfg.col,
            border = cfg.border,
        }

        debug.log("update_float_geometry", function()
            local w = vim.api.nvim_win_get_width(float_win)
            local h = vim.api.nvim_win_get_height(float_win)
            return {
                term_buf = term_buf,
                from_mode = original_mode,
                to_mode = "fullscreen",
                float_win = float_win,
                border = "single",
                height_formula = tostring(vim.o.lines) .. "-" .. tostring(vim.o.cmdheight) .. "-3=" .. tostring(
                    vim.o.lines - vim.o.cmdheight - 3
                ),
                width = vim.o.columns,
                win_width = w,
                win_height = h,
                editor_lines = vim.o.lines,
                editor_columns = vim.o.columns,
                cmdheight = vim.o.cmdheight,
            }
        end)
        pcall(vim.api.nvim_win_set_config, float_win, {
            relative = "editor",
            width = vim.o.columns,
            height = vim.o.lines - vim.o.cmdheight - 3,
            row = 0,
            col = 0,
            style = "minimal",
            border = "single",
        })

        data.mode = "fullscreen"
        layout.apply_geometry(term_buf)
    else
        debug.log("update_float_geometry", function()
            local w = vim.api.nvim_win_get_width(float_win)
            local h = vim.api.nvim_win_get_height(float_win)
            return {
                term_buf = term_buf,
                from_mode = original_mode,
                to_mode = "float",
                float_win = float_win,
                win_width = w,
                win_height = h,
                editor_lines = vim.o.lines,
                editor_columns = vim.o.columns,
            }
        end)
        local orig = data.float_original
        if orig then
            data.mode = "float"
            layout.apply_geometry(term_buf)
            data.float_original = nil
        end
    end

    if should_focus then
        vim.api.nvim_set_current_win(float_win)
        vim.schedule(function()
            if state.is_valid_win(float_win) then
                vim.cmd("startinsert")
            end
        end)
    end
end

--- Setup fullscreen feature (returns false if disabled)
--- @param term_buf number Terminal buffer
--- @param win_opts table Window options
--- @return boolean true if enabled
function M.setup(term_buf, win_opts)
    if config.options.window_features and config.options.window_features.fullscreen == false then
        return false
    end
    return true
end

return M
