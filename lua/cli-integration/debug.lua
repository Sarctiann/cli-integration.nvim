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

return M
