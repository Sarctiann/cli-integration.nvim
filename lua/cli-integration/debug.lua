--- Debug logging module for cli-integration.nvim
--- Zero-overhead when config.options.debug is false: single early-return check.
--- When debug is true, appends structured log entries to cli-integration-debug.log in cwd.
local config = require("cli-integration.config")

local M = {}

--- Format a timestamp string in YYYY-MM-DD HH:MM:SS format
--- @return string|osdate
local function get_timestamp()
	return os.date("%Y-%m-%d %H:%M:%S")
end

--- Alias tracking for long cli_cmd values to reduce log verbosity.
--- First occurrence stores full value and assigns alias "[cmd:1]", "[cmd:2]", etc.
--- Subsequent occurrences show only the alias.
M._cmd_aliases = {}
M._cmd_alias_counter = 0

--- Replace long cmd/cli_cmd strings with aliases.
--- @param data table
--- @return table
local function maybe_alias_cmd(data)
	if not data then
		return data
	end
	local result = {}
	for k, v in pairs(data) do
		if type(v) == "string" and (k == "cmd" or k == "cli_cmd") and #v > 80 then
			local alias = M._cmd_aliases[v]
			if not alias then
				M._cmd_alias_counter = M._cmd_alias_counter + 1
				alias = string.format("[cmd:%d]", M._cmd_alias_counter)
				M._cmd_aliases[v] = alias
				-- First occurrence: show alias + truncated preview
				result[k] = alias .. " " .. v:sub(1, 60) .. "..."
			else
				-- Subsequent: alias only
				result[k] = alias
			end
		else
			result[k] = v
		end
	end
	return result
end

--- Format a data table into key=value pairs separated by spaces
--- @param data table|nil Key-value data to format
--- @return string
local function format_data(data)
	if not data then
		return ""
	end
	local parts = {}
	for key, value in pairs(data) do
		local value_str
		if value == nil then
			value_str = "nil"
		elseif type(value) == "boolean" then
			value_str = value and "true" or "false"
		elseif type(value) == "number" then
			value_str = tostring(value)
		else
			value_str = tostring(value)
		end
		table.insert(parts, tostring(key) .. "=" .. value_str)
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

--- Log a debug event to file.
--- Zero-overhead when debug is disabled: early return before any work.
--- @param event string Event name (e.g., "toggle_fullscreen", "create_terminal")
--- @param data_fn fun():table Lazy function returning data to log
function M.log(event, data_fn)
	if not config.options.debug then
		return
	end

	local ok, data = pcall(data_fn)
	if not ok then
		return
	end

	data = maybe_alias_cmd(data)

	local timestamp = get_timestamp()
	local data_str = format_data(data)
	local entry = "[" .. timestamp .. "] [cli-integration] " .. event
	if data_str ~= "" then
		entry = entry .. " | " .. data_str
	end

	local log_path = vim.fn.getcwd() .. "/cli-integration-debug.log"
	local file = io.open(log_path, "a")
	if file then
		file:write(entry .. "\n")
		file:close()
	end
end

--- Snapshot of every window's size/content, keyed by win id, from the last
--- call to M.win_tree_diff. Used to log only what actually changed instead
--- of the whole tree every time, so a burst of calls stays readable.
M._win_snapshot = nil

--- Take a full-tabpage window snapshot and log only what changed since the
--- last call: new windows, closed windows, and windows whose width/height
--- changed (with old->new and their buffer's buftype/filetype/name so we can
--- tell apart the sidebar, Snacks.explorer, the dashboard, floats, etc).
--- Call this at multiple points around a suspected layout-shrink (e.g.
--- before and after reacting to WinResized) to see the *sequence* of who
--- actually changed size, not just our own tracked windows.
--- @param label string Free-form tag identifying the call site/phase
function M.win_tree_diff(label)
	if not config.options.debug then
		return
	end

	local snapshot = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local ok_w, w = pcall(vim.api.nvim_win_get_width, win)
		local ok_h, h = pcall(vim.api.nvim_win_get_height, win)
		if ok_w and ok_h then
			local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, win)
			local ok_cfg, cfg = pcall(vim.api.nvim_win_get_config, win)
			snapshot[win] = {
				w = w,
				h = h,
				buf = ok_buf and buf or -1,
				buftype = ok_buf and vim.bo[buf].buftype or "?",
				filetype = ok_buf and vim.bo[buf].filetype or "?",
				name = ok_buf and vim.api.nvim_buf_get_name(buf) or "?",
				relative = ok_cfg and cfg.relative or "?",
			}
		end
	end

	local previous = M._win_snapshot
	if previous then
		for win, info in pairs(snapshot) do
			local prev = previous[win]
			if not prev then
				M.log("win_tree_new_window", function()
					return {
						phase = label,
						win = win,
						w = info.w,
						h = info.h,
						buftype = info.buftype,
						filetype = info.filetype,
						relative = info.relative,
						name = info.name,
					}
				end)
			elseif prev.w ~= info.w or prev.h ~= info.h then
				M.log("win_tree_size_changed", function()
					return {
						phase = label,
						win = win,
						old_w = prev.w,
						old_h = prev.h,
						new_w = info.w,
						new_h = info.h,
						buftype = info.buftype,
						filetype = info.filetype,
						relative = info.relative,
						name = info.name,
					}
				end)
			end
		end
		for win, prev in pairs(previous) do
			if not snapshot[win] then
				M.log("win_tree_closed_window", function()
					return { phase = label, win = win, last_w = prev.w, last_h = prev.h, buftype = prev.buftype }
				end)
			end
		end
	end

	M._win_snapshot = snapshot
end

--- Register global debug autocommands for monitoring file operations, bufferline,
--- and window focus. Only active when config.options.debug is true.
function M.setup_autocmds()
	if not config.options.debug then
		return
	end

	local group = vim.api.nvim_create_augroup("CliIntegrationDebug", { clear = true })

	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "showtabline,cmdheight,laststatus",
		callback = function()
			M.log("debug_global_chrome_option_set", function()
				return {
					option = vim.v.option_name,
					old = vim.v.option_old,
					new = vim.v.option_new,
					stack = debug.traceback("", 2):gsub("\n", " <- "):sub(1, 300),
				}
			end)
		end,
		desc = "Debug: log changes to global chrome options (tabline/cmdline/statusline) that shrink/grow every window",
	})

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
		group = group,
		pattern = "*",
		callback = function(args)
			M.log("debug_file_opened", function()
				local bufname = vim.api.nvim_buf_get_name(args.buf)
				return { buf = args.buf, file = bufname, event = args.event }
			end)
			M.win_tree_diff("after_" .. args.event)
		end,
		desc = "Debug: log file opens",
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = group,
		pattern = "*",
		callback = function(args)
			M.log("debug_file_closed", function()
				return { buf = args.buf, event = args.event }
			end)
			M.win_tree_diff("after_" .. args.event)
		end,
		desc = "Debug: log file closes",
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		pattern = "*",
		callback = function()
			local win = vim.api.nvim_get_current_win()
			local buf = vim.api.nvim_get_current_buf()
			local bufname = vim.api.nvim_buf_get_name(buf)
			local bt = vim.bo[buf].buftype
			local win_cfg = vim.api.nvim_win_get_config(win)
			local is_float = win_cfg.relative ~= ""
			M.log("debug_win_enter", function()
				return {
					win = win,
					buf = buf,
					buftype = bt,
					name = bufname,
					float = is_float,
				}
			end)
			M.win_tree_diff("after_WinEnter")
		end,
		desc = "Debug: log window focus changes",
	})

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		pattern = "*",
		callback = function(args)
			local bufname = vim.api.nvim_buf_get_name(args.buf)
			local bt = vim.bo[args.buf].buftype
			local win = vim.api.nvim_get_current_win()
			local win_cfg = vim.api.nvim_win_get_config(win)
			local is_float = win_cfg.relative ~= ""
			M.log("debug_buf_enter", function()
				return {
					buf = args.buf,
					buftype = bt,
					name = bufname,
					win = win,
					win_float = is_float,
				}
			end)
			M.win_tree_diff("after_BufEnter")
		end,
		desc = "Debug: log buffer focus changes",
	})

	vim.api.nvim_create_autocmd({ "WinNew", "WinClosed" }, {
		group = group,
		pattern = "*",
		callback = function(args)
			M.win_tree_diff("after_" .. args.event)
		end,
		desc = "Debug: snapshot window tree on window create/close",
	})
end

return M
