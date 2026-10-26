--- @module 'cli-integration.window.geometry'
local M = {}

-- PTY sizing is owned entirely by Neovim: whenever a window showing a terminal
-- changes geometry or buffer, Nvim resizes the PTY to that window's text area
-- (width - textoff, height). We never call jobresize ourselves — doing so only
-- races Nvim's own (deferred) resize and leaves the TUI and the visible area out
-- of sync. Keep a terminal buffer in ONE window at a time, since Nvim uses the
-- max size across all windows showing it.

--- Build terminal job environment
--- @param opts table
--- @param cols number
--- @param lines number
--- @return table<string, string>
function M.build_job_env(opts, cols, lines)
    local env = vim.fn.environ()
    env.TMUX = nil
    env.TMUX_PANE = nil
    env.TERM_PROGRAM = nil
    env.TERM_PROGRAM_VERSION = nil
    env.GHOSTTY_RESOURCES_DIR = nil
    env.GHOSTTY_SHELL_FEATURES = nil
    env.GHOSTTY_BIN_DIR = nil
    env.TERMINFO = nil
    env.COLUMNS = tostring(cols)
    env.LINES = tostring(lines)
    if not (type(opts.env) == "table" and opts.env.TERM ~= nil) then
        env.TERM = "xterm-256color"
    end
    if not (type(opts.env) == "table" and opts.env.COLORTERM ~= nil) then
        env.COLORTERM = "truecolor"
    end
    if type(opts.env) == "table" then
        env = vim.tbl_extend("force", env, opts.env)
    end
    if type(opts.unset_env) == "table" then
        for _, key in ipairs(opts.unset_env) do
            env[key] = nil
        end
    end
    return env
end

--- Calculate width based on config (percentage or absolute)
--- @param width_config number Width configuration (1-100 for percentage, >100 for absolute)
--- @return number Calculated width in columns
function M.calculate_width(width_config)
    local editor_width = vim.o.columns
    if width_config <= 100 then
        local percentage = width_config <= 1 and width_config or (width_config / 100)
        return math.floor(editor_width * percentage)
    end
    return width_config
end

--- Calculate the usable content dimensions of a terminal window, matching the
--- size Nvim itself gives the PTY (text area: width minus foldcolumn/textoff)
--- @param win number Window handle (must be valid and sized)
--- @return number cols Usable columns
--- @return number lines Usable lines
function M.calculate_content_dimensions(win)
    local w = vim.api.nvim_win_get_width(win)
    local h = vim.api.nvim_win_get_height(win)
    local textoff = (vim.fn.getwininfo(win)[1] or {}).textoff or 0
    local cols = math.max(1, w - textoff)
    local lines = math.max(1, h)
    return cols, lines
end

--- Calculate geometry based on mode
--- @param data table The sidebar entry
--- @return table {width, height, row, col, relative}
function M.get_geometry(data)
    if data.mode == "fullscreen" then
        return {
            relative = "editor",
            width = vim.o.columns,
            height = vim.o.lines - vim.o.cmdheight - 3,
            row = 0,
            col = 0,
        }
    elseif data.mode == "sidebar" then
        return {
            width = M.calculate_width(data.width_config),
            height = vim.o.lines - vim.o.cmdheight,
        }
    else -- float
        return {
            relative = "editor",
            width = data.float_original and data.float_original.width or data.width_config,
            height = data.float_original and data.float_original.height or 30,
            row = data.float_original and data.float_original.row or math.floor((vim.o.lines - 30) / 2),
            col = data.float_original and data.float_original.col
                or math.floor((vim.o.columns - data.width_config) / 2),
        }
    end
end

return M
