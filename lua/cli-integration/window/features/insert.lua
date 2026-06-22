--- @module 'cli-integration.window.features.insert'
local M = {}
local state = require("cli-integration.window.state")
local debug = require("cli-integration.debug")
local config = require("cli-integration.config")

--- Setup auto insert feature
--- @param term_buf number Terminal buffer
--- @param win_opts table Window options
--- @return boolean true if enabled
function M.setup(term_buf, win_opts)
    if config.options.window_features and config.options.window_features.auto_insert == false then
        return false
    end

    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
        buffer = term_buf,
        callback = function(ev)
            debug.log("terminal_WinEnter_startinsert", function()
                local data = state.sidebars[term_buf]
                local sw = data and data.sidebar_win
                local h = sw and state.is_valid_win(sw) and vim.api.nvim_win_get_height(sw) or -1
                return {
                    term_buf = term_buf,
                    event = ev.event,
                    current_win = vim.api.nvim_get_current_win(),
                    sidebar_win_height = h,
                }
            end)
            if vim.bo[term_buf].buftype == "terminal" then
                vim.cmd("startinsert")
            end
        end,
        desc = "Auto-enter insert mode in terminal",
    })

    if win_opts.start_insert_on_click then
        if config.options.window_features and config.options.window_features.start_insert_on_click == false then
            return true
        end
        local click_opts = { buffer = term_buf, noremap = true, silent = true, expr = true }
        local click_fn = function()
            local mouse_pos = vim.fn.getmousepos()
            local current_win = vim.api.nvim_get_current_win()
            if mouse_pos.winid == current_win and state.is_integration_window(current_win, term_buf) then
                return "i"
            else
                return "<LeftMouse>"
            end
        end
        vim.keymap.set("n", "<LeftMouse>", click_fn, click_opts)
        vim.keymap.set("n", "<2-LeftMouse>", click_fn, click_opts)
    end

    return true
end

return M
