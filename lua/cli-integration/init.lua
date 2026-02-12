--- @module 'Cli-Integration'

local config = require("cli-integration.config")
local commands = require("cli-integration.commands")
local autocmds = require("cli-integration.autocmds")

local M = {}

--- Setup function for the plugin
--- @param user_config Cli-Integration.Config
--- @return nil
function M.setup(user_config)
	-- Setup configuration
	local configs = config.setup(user_config)

	-- Create user command to open CLI tool
	vim.api.nvim_create_user_command("CLIIntegration", function(opts)
		-- Validate integrations before executing
		local integrations = configs.integrations or {}
		if not integrations or #integrations == 0 then
			vim.notify(
				"cli-integration.nvim: No integrations configured. Please configure at least one integration with 'cli_cmd' and 'name'.",
				vim.log.levels.ERROR
			)
			return
		end

		-- Parse arguments: first is action, second is integration name, rest are CLI args
		local fargs = opts.fargs or {}
		local action = fargs[1] or ""
		local integration_name = fargs[2]

		-- Convert underscores back to spaces in integration name (for autocompletion compatibility)
		if integration_name then
			integration_name = integration_name:gsub("_", " ")
		end

		-- Extract CLI arguments (everything after integration name)
		local cli_args = nil
		if #fargs > 2 then
			local args_table = {}
			for i = 3, #fargs do
				table.insert(args_table, fargs[i])
			end
			cli_args = table.concat(args_table, " ")
		end

		-- Execute command with error handling
		local ok, err = pcall(function()
			if action == "open_cwd" or action == "" or not action then
				commands.open_cwd(integration_name, cli_args)
			elseif action == "open_root" then
				commands.open_git_root(integration_name, cli_args)
			else
				-- Backward compatibility: if first arg is not a known action, treat it as integration name
				-- Convert underscores back to spaces (for autocompletion compatibility)
				local name = action:gsub("_", " ")
				-- In backward compatibility mode, integration name is first arg, so CLI args start from second
				local backward_cli_args = nil
				if #fargs > 1 then
					local args_table = {}
					for i = 2, #fargs do
						table.insert(args_table, fargs[i])
					end
					backward_cli_args = table.concat(args_table, " ")
				end
				commands.open_cwd(name, backward_cli_args)
			end
		end)

		if not ok then
			vim.notify("cli-integration.nvim: Error executing command: " .. tostring(err), vim.log.levels.ERROR)
		end
	end, {
		nargs = "*",
		complete = function(_, cmd_line, cursor_pos)
			-- Parse the command line to determine which argument we're completing
			-- cmd_line contains the full command line up to cursor_pos
			-- Extract the substring up to cursor position
			local cmd_substr = cmd_line:sub(1, cursor_pos)

			-- Trim leading and trailing whitespace
			cmd_substr = cmd_substr:match("^%s*(.-)%s*$") or ""

			-- Split by one or more whitespace characters
			-- Use a more robust splitting that handles multiple spaces correctly
			local args = {}
			for part in cmd_substr:gmatch("%S+") do
				table.insert(args, part)
			end

			-- Remove the command name itself (first element: "CLIIntegration")
			if #args > 0 and args[1] == "CLIIntegration" then
				table.remove(args, 1)
			end

			-- If no arguments, show actions
			if #args == 0 then
				return { "open_cwd", "open_root" }
			end

			-- If first argument is a known action, show integration names
			if args[1] == "open_cwd" or args[1] == "open_root" then
				local integrations = configs.integrations or {}
				local names = {}
				for _, integration in ipairs(integrations) do
					-- Replace spaces with underscores for autocompletion display
					local display_name = integration.name:gsub(" ", "_")
					table.insert(names, display_name)
				end
				return names
			end

			-- If first argument is not a known action and we're completing it, show actions
			if #args == 1 then
				return { "open_cwd", "open_root" }
			end

			-- If we already have two arguments, no more completions
			return {}
		end,
		desc = "Open CLI Integration",
	})

	-- Setup autocommands
	autocmds.setup(configs)
end

return M
