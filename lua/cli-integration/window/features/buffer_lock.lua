--- @module 'cli-integration.window.features.buffer_lock'
local M = {}
local state = require("cli-integration.window.state")
local debug = require("cli-integration.debug")
local config = require("cli-integration.config")

--- Setup buffer lock autocmds
--- @param term_buf number Terminal buffer
--- @return boolean true if enabled
function M.setup(term_buf)
    if config.options.window_features and config.options.window_features.buffer_lock == false then
        return false
    end

    vim.api.nvim_create_autocmd("BufWinEnter", {
        callback = function(args)
            if args.buf == term_buf then
                return
            end

            local current_win = vim.api.nvim_get_current_win()
            local data = state.sidebars[term_buf]
            local is_our_win = data ~= nil and (current_win == data.sidebar_win or current_win == data.float_win)

            debug.log("BufWinEnter_lock", function()
                local sw = data and data.sidebar_win
                local h = sw and state.is_valid_win(sw) and vim.api.nvim_win_get_height(sw) or -1
                return {
                    term_buf = term_buf,
                    event_buf = args.buf,
                    current_win = current_win,
                    is_our_win = is_our_win,
                    sidebar_win_height = h,
                }
            end)

            if is_our_win then
                vim.schedule(function()
                    if not vim.api.nvim_win_is_valid(current_win) or not vim.api.nvim_buf_is_valid(term_buf) then
                        return
                    end

                    pcall(vim.api.nvim_win_set_buf, current_win, term_buf)

                    local target_win = nil
                    local fallback_win = nil
                    for _, w in ipairs(vim.api.nvim_list_wins()) do
                        if w ~= current_win and vim.api.nvim_win_is_valid(w) then
                            local b = vim.api.nvim_win_get_buf(w)
                            local bt = vim.bo[b].buftype
                            if bt == "" then
                                target_win = w
                                break
                            elseif not fallback_win and bt ~= "terminal" and bt ~= "nofile" then
                                fallback_win = w
                            end
                        end
                    end

                    local dest = target_win or fallback_win
                    if not dest then
                        local layout = require("cli-integration.window.layout")
                        local anchor = layout.find_layout_anchor_window()
                        if anchor and vim.api.nvim_win_is_valid(anchor) then
                            vim.api.nvim_set_current_win(anchor)
                        end
                        vim.cmd("vsplit")
                        dest = vim.api.nvim_get_current_win()
                    end

                    if dest and vim.api.nvim_buf_is_valid(args.buf) then
                        vim.api.nvim_set_current_win(dest)
                        pcall(vim.api.nvim_win_set_buf, dest, args.buf)
                    end
                end)
                return
            end

            if args.buf == term_buf then
                local integration_win = nil
                if data then
                    if data.sidebar_win and vim.api.nvim_win_is_valid(data.sidebar_win) then
                        integration_win = data.sidebar_win
                    elseif data.float_win and vim.api.nvim_win_is_valid(data.float_win) then
                        integration_win = data.float_win
                    end
                end
                if integration_win then
                    vim.api.nvim_set_current_win(integration_win)
                    vim.schedule(function()
                        if vim.api.nvim_win_is_valid(integration_win) then
                            vim.cmd("startinsert")
                        end
                    end)
                end
            end
        end,
        desc = "Lock terminal window to terminal buffer only; handle list_buffer window separation",
    })

    vim.api.nvim_create_autocmd("WinEnter", {
        callback = function()
            local current_win = vim.api.nvim_get_current_win()
            if not state.is_integration_window(current_win, term_buf) then
                return
            end
            local cur_buf = vim.api.nvim_get_current_buf()
            debug.log("WinEnter_guard", function()
                local data = state.sidebars[term_buf]
                local sw = data and data.sidebar_win
                local h = sw and state.is_valid_win(sw) and vim.api.nvim_win_get_height(sw) or -1
                return {
                    term_buf = term_buf,
                    current_win = current_win,
                    current_buf = cur_buf,
                    is_wrong_buf = cur_buf ~= term_buf,
                    sidebar_win_height = h,
                }
            end)
            if cur_buf ~= term_buf and vim.api.nvim_buf_is_valid(term_buf) and vim.api.nvim_win_is_valid(current_win) then
                pcall(vim.api.nvim_win_set_buf, current_win, term_buf)
            end
        end,
        desc = "Secondary guard: restore terminal buffer on WinEnter in integration window",
    })

    return true
end

return M
