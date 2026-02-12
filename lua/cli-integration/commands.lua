--- Commands module for opening CLI tool in different modes
local terminal = require("cli-integration.terminal")
local config = require("cli-integration.config")

local M = {}

--- Get integration by index or cli_cmd
--- @param identifier number|string|nil Integration index (1-based) or cli_cmd string
--- @return Cli-Integration.Integration|nil
--- @return string|nil Error message if integration not found
local function get_integration(identifier)
	local integrations = config.options.integrations or {}
	if not integrations or #integrations == 0 then
		return nil, "No integrations configured. Please configure at least one integration with 'cli_cmd'."
	end

	if not identifier then
		-- Default to first integration
		return integrations[1], nil
	end

	if type(identifier) == "number" then
		if identifier < 1 or identifier > #integrations then
			return nil, "Integration index " .. identifier .. " is out of range (1-" .. #integrations .. ")"
		end
		return integrations[identifier], nil
	elseif type(identifier) == "string" then
		-- Find by cli_cmd
		for _, integration in ipairs(integrations) do
			if integration.cli_cmd == identifier then
				return integration, nil
			end
		end
		return nil, "Integration with cli_cmd '" .. identifier .. "' not found"
	end

	return nil, "Invalid identifier type. Expected number or string."
end

--- Open CLI tool in the current file's directory
--- @param integration_identifier number|string|nil Integration index or cli_cmd (defaults to first integration)
--- @return nil
function M.open_cwd(integration_identifier)
	local integration, err = get_integration(integration_identifier)
	if not integration then
		if err then
			vim.notify("cli-integration.nvim: " .. err, vim.log.levels.WARN)
		end
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
	local integration, err = get_integration(integration_identifier)
	if not integration then
		if err then
			vim.notify("cli-integration.nvim: " .. err, vim.log.levels.WARN)
		end
		return
	end

	local current_file = vim.fn.expand("%:p")
	local current_dir = vim.fn.expand("%:p:h")

	local git_root = vim.fs.find({ ".git" }, {
		path = current_file ~= "" and current_file or current_dir,
		upward = true,
	})[1]

	local working_dir
	if git_root then
		working_dir = vim.fn.fnamemodify(git_root, ":h")
	else
		working_dir = current_dir ~= "" and current_dir or vim.fn.getcwd()
		-- Inform user that git root was not found
		vim.notify(
			"cli-integration.nvim: Git root not found, using current directory: " .. working_dir,
			vim.log.levels.INFO
		)
	end

	terminal.open_terminal(integration, nil, nil, working_dir)
end

--- Open CLI tool with custom arguments
--- @param args string Custom arguments for CLI tool
--- @param keep_open boolean|nil Whether to keep the terminal open
--- @param integration_identifier number|string|nil Integration index or cli_cmd (defaults to first integration)
--- @return nil
function M.open_custom(args, keep_open, integration_identifier)
	local integration, err = get_integration(integration_identifier)
	if not integration then
		if err then
			vim.notify("cli-integration.nvim: " .. err, vim.log.levels.WARN)
		end
		return
	end

	if not args or args == "" then
		vim.notify("cli-integration.nvim: Custom arguments cannot be empty", vim.log.levels.WARN)
		return
	end

	terminal.open_terminal(integration, args, keep_open)
end

return M
