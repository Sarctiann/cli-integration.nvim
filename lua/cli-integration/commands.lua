--- Commands module for opening CLI tool in different modes
local terminal = require("cli-integration.terminal")
local config = require("cli-integration.config")

local M = {}

--- Get integration by index or cli_cmd
--- @param identifier number|string|nil Integration index (1-based) or cli_cmd string
--- @return cli-integration.Integration|nil
local function get_integration(identifier)
	local integrations = config.options.integrations or {}
	if not integrations or #integrations == 0 then
		return nil
	end

	if not identifier then
		-- Default to first integration
		return integrations[1]
	end

	if type(identifier) == "number" then
		return integrations[identifier]
	elseif type(identifier) == "string" then
		-- Find by cli_cmd
		for _, integration in ipairs(integrations) do
			if integration.cli_cmd == identifier then
				return integration
			end
		end
	end

	return nil
end

--- Open CLI tool in the current file's directory
--- @param integration_identifier number|string|nil Integration index or cli_cmd (defaults to first integration)
--- @return nil
function M.open_cwd(integration_identifier)
	local integration = get_integration(integration_identifier)
	if not integration then
		return
	end

	local working_dir = vim.fn.expand("%:p:h")
	if working_dir == "" then
		working_dir = vim.fn.getcwd()
	end

	terminal.open_terminal(integration, nil, nil, working_dir)
end

--- Open CLI tool in the project root (git root)
--- @param integration_identifier number|string|nil Integration index or cli_cmd (defaults to first integration)
--- @return nil
function M.open_git_root(integration_identifier)
	local integration = get_integration(integration_identifier)
	if not integration then
		return
	end

	local current_file = vim.fn.expand("%:p")
	local current_dir = vim.fn.expand("%:p:h")

	local working_dir = vim.fs.find({ ".git" }, {
		path = current_file,
		upward = true,
	})[1]

	if working_dir then
		working_dir = vim.fn.fnamemodify(working_dir, ":h")
	else
		working_dir = current_dir ~= "" and current_dir or vim.fn.getcwd()
	end

	terminal.open_terminal(integration, nil, nil, working_dir)
end

--- Open CLI tool with custom arguments
--- @param args string Custom arguments for CLI tool
--- @param keep_open boolean|nil Whether to keep the terminal open
--- @param integration_identifier number|string|nil Integration index or cli_cmd (defaults to first integration)
--- @return nil
function M.open_custom(args, keep_open, integration_identifier)
	local integration = get_integration(integration_identifier)
	if not integration then
		return
	end

	terminal.open_terminal(integration, args, keep_open)
end

return M
