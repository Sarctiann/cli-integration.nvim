--- Help system module
local config = require("cli-integration.config")

local M = {}

--- Check if Snacks is available
--- @return boolean
local function has_snacks()
	return type(Snacks) == "table" and type(Snacks.notify) == "function"
end

--- Format array of keys into a string with separators
--- @param keys string[] Array of key combinations
--- @return string Formatted string with keys joined by " | "
local function format_keys(keys)
	return table.concat(keys, " | ")
end

--- Calculate the maximum width of key strings in a list of entries
--- @param entries table[] Array of { keys, description } tables
--- @return number Maximum width
local function get_max_key_width(entries)
	local max_width = 0
	for _, entry in ipairs(entries) do
		if entry.separator then
			-- Skip separators
		elseif entry.keys then
			local key_str = format_keys(entry.keys)
			if #key_str > max_width then
				max_width = #key_str
			end
		elseif entry.key_str then
			if #entry.key_str > max_width then
				max_width = #entry.key_str
			end
		end
	end
	return max_width
end

--- Format a help line with proper alignment
--- @param keys string|string[]|nil Key combination(s) or fixed key string
--- @param description string Description text
--- @param key_width number Width to align keys to
--- @return string Formatted line
local function format_help_line(keys, description, key_width)
	local key_str
	if type(keys) == "table" then
		key_str = format_keys(keys)
	elseif type(keys) == "string" then
		key_str = keys
	else
		key_str = ""
	end
	local padding = string.rep(" ", math.max(1, key_width - #key_str + 1))
	return "    · " .. key_str .. padding .. ": " .. description
end

--- Generate help text from configuration
--- @return string Formatted help text
local function generate_help_text()
	local terminal = require("cli-integration.terminal")
	local current_buf = vim.api.nvim_get_current_buf()

	-- Get integration for current terminal buffer
	local integration = terminal.get_integration_for_buf(current_buf)

	-- Get terminal keys and cli_cmd from integration or fallback to global defaults
	local keys = nil
	local cli_cmd = "CLI Tool"

	if integration and integration.terminal_keys then
		keys = integration.terminal_keys
		cli_cmd = integration.cli_cmd or "CLI Tool"
	else
		-- Fallback to global defaults
		keys = config.options.terminal_keys
		cli_cmd = "CLI Tool"
	end

	if not keys or not keys.terminal_mode or not keys.normal_mode then
		return ""
	end

	local lines = {}

	-- Terminal Mode section
	table.insert(lines, "Term Mode:")
	local term_entries = {
		{ keys = keys.terminal_mode.submit, description = "Submit" },
		{ keys = keys.terminal_mode.enter, description = "Send Enter Key" },
		{ keys = keys.terminal_mode.normal_mode, description = "Normal Mode" },
		{ keys = keys.terminal_mode.insert_file_path, description = "Add Buffer File Path" },
		{ keys = keys.terminal_mode.insert_all_buffers, description = "Add All Open Buffer File Paths" },
		{ keys = keys.terminal_mode.toggle_width, description = "Toggle Window Width" },
		{ separator = true },
		{ keys = keys.terminal_mode.new_lines, description = "New Line" },
		{ keys = keys.terminal_mode.help, description = "Show Help" },
		{ separator = true },
		{ key_str = "<C-c>", description = "Clear/Stop/Close" },
		{ key_str = "<C-d>", description = "Close" },
		{ key_str = "<C-r>", description = "Review Changes" },
	}
	local term_key_width = get_max_key_width(term_entries)
	for _, entry in ipairs(term_entries) do
		if entry.separator then
			table.insert(lines, "    ---")
		elseif entry.keys then
			-- Validate keys is an array
			if type(entry.keys) == "table" then
				table.insert(lines, format_help_line(entry.keys, entry.description, term_key_width))
			end
		elseif entry.key_str then
			table.insert(lines, format_help_line(entry.key_str, entry.description, term_key_width))
		end
	end
	table.insert(lines, "")

	-- Normal Mode section
	table.insert(lines, "Norm Mode:")
	local norm_entries = {
		{ keys = keys.normal_mode.hide, description = "Hide" },
		{ keys = keys.normal_mode.toggle_width, description = "Toggle Window Width" },
		{ key_str = "<...>", description = "(all other normal mode keys)" },
	}
	local norm_key_width = get_max_key_width(norm_entries)
	for _, entry in ipairs(norm_entries) do
		if entry.keys then
			-- Validate keys is an array
			if type(entry.keys) == "table" then
				table.insert(lines, format_help_line(entry.keys, entry.description, norm_key_width))
			end
		elseif entry.key_str then
			table.insert(lines, format_help_line(entry.key_str, entry.description, norm_key_width))
		end
	end
	table.insert(lines, "")

	-- CLI tool commands section
	table.insert(lines, cli_cmd .. " commands:")
	local cmd_entries = {
		{ key_str = "quit | exit", description = "(<CR>) Close " .. cli_cmd },
		{ separator = true },
		{ key_str = "/", description = "Show command list" },
		{ key_str = "@", description = "Show file list to attach" },
		{ key_str = "!", description = "To run in the shell" },
	}
	local cmd_key_width = get_max_key_width(cmd_entries)
	for _, entry in ipairs(cmd_entries) do
		if entry.separator then
			table.insert(lines, "    ---")
		else
			table.insert(lines, format_help_line(entry.key_str, entry.description, cmd_key_width))
		end
	end

	return table.concat(lines, "\n")
end

--- Show help notification with keymaps and commands
--- @return nil
function M.show_help()
	if not has_snacks() then
		vim.notify("cli-integration.nvim: Snacks.nvim is required but not available", vim.log.levels.ERROR)
		return
	end

	local help_text = generate_help_text()
	if help_text == "" then
		return
	end

	Snacks.notify(help_text, { title = "Keymaps", style = "compact", history = false, timeout = 5000 })
end

--- Show quick help notification on terminal open
--- @return nil
function M.show_quick_help()
	if not has_snacks() then
		return
	end

	local terminal = require("cli-integration.terminal")
	local current_buf = vim.api.nvim_get_current_buf()

	-- Get integration for current terminal buffer
	local integration = terminal.get_integration_for_buf(current_buf)

	-- Get terminal keys from integration or fallback to global defaults
	local keys = nil

	if integration and integration.terminal_keys then
		keys = integration.terminal_keys
	else
		-- Fallback to global defaults
		keys = config.options.terminal_keys
	end

	if not keys or not keys.terminal_mode or not keys.terminal_mode.help then
		return
	end

	local help_keys = {}
	for _, key in ipairs(keys.terminal_mode.help) do
		table.insert(help_keys, "[" .. key .. "]")
	end
	local help_text = " Press: " .. table.concat(help_keys, " | ") .. " to Show Help "
	Snacks.notify(help_text, { title = "", style = "compact", history = false, timeout = 3000 })
end

return M
