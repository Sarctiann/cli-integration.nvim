--- @module 'cli-integration.window.features.dynamic_resize'
local M = {}
local state = require("cli-integration.window.state")
local geometry = require("cli-integration.window.geometry")
local debug = require("cli-integration.debug")
local config = require("cli-integration.config")

M._autocmd_setup = false
M._last_editor_width = 0
M._last_editor_height = 0

--- Resize all sidebar/float windows
local function resize_sidebars()
    local columns_changed = vim.o.columns ~= M._last_editor_width
    local lines_changed = vim.o.lines ~= M._last_editor_height

    if columns_changed then
        M._last_editor_width = vim.o.columns
    end
    if lines_changed then
        M._last_editor_height = vim.o.lines
    end

    debug.log("resize_sidebars", function()
        local sidebar_info = {}
        for buf, data in pairs(state.sidebars) do
            sidebar_info[buf] = {
                mode = data.mode,
                sidebar_win = data.sidebar_win,
                win_width = data.sidebar_win and state.is_valid_win(data.sidebar_win) and vim.api.nvim_win_get_width(
                    data.sidebar_win
                ) or nil,
                win_height = data.sidebar_win and state.is_valid_win(data.sidebar_win) and vim.api.nvim_win_get_height(
                    data.sidebar_win
                ) or nil,
            }
        end
        return {
            columns_changed = columns_changed,
            lines_changed = lines_changed,
            editor_width = vim.o.columns,
            editor_lines = vim.o.lines,
            cmdheight = vim.o.cmdheight,
            num_sidebars = vim.tbl_count(state.sidebars),
            sidebars = sidebar_info,
        }
    end)

    for _, data in pairs(state.sidebars) do
        if data.mode == "sidebar" and state.is_valid_win(data.sidebar_win) then
            if columns_changed then
                local w = geometry.calculate_width(data.width_config)
                pcall(vim.api.nvim_win_set_width, data.sidebar_win, w)
            end
        elseif data.float_win and state.is_valid_win(data.float_win) then
            if columns_changed or lines_changed then
                require("cli-integration.window.layout").apply_geometry(data.term_buf)
                local cw = vim.api.nvim_win_get_width(data.float_win)
                local ch = vim.api.nvim_win_get_height(data.float_win)
                data._last_pty_width = cw
                data._last_pty_height = ch
            else
                local cw = vim.api.nvim_win_get_width(data.float_win)
                local ch = vim.api.nvim_win_get_height(data.float_win)
                if cw ~= data._last_pty_width or ch ~= data._last_pty_height then
                    geometry.resize_pty(data.term_buf, data.float_win, 0)
                    data._last_pty_width = cw
                    data._last_pty_height = ch
                end
            end
        end
    end
end

--- Setup dynamic resize autocmds
--- @return boolean true if enabled
function M.setup()
    if config.options.window_features and config.options.window_features.dynamic_resize == false then
        return false
    end

    M._last_editor_width = vim.o.columns
    M._last_editor_height = vim.o.lines

    if not M._autocmd_setup then
        local group = vim.api.nvim_create_augroup("CliIntegrationResize", { clear = true })
        vim.api.nvim_create_autocmd("VimResized", {
            group = group,
            callback = function()
                debug.log("VimResized_fired", function()
                    return {
                        editor_width = vim.o.columns,
                        editor_lines = vim.o.lines,
                        cmdheight = vim.o.cmdheight,
                        showtabline = vim.o.showtabline,
                    }
                end)
                resize_sidebars()
            end,
            desc = "Restore sidebar width on editor resize",
        })

        M._autocmd_setup = true
    end

    return true
end

return M
