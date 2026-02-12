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

	-- Validate that at least one integration is configured
	local integrations = configs.integrations or {}
	if not integrations or #integrations == 0 then
		vim.notify(
			"cli-integration.nvim: No integrations configured. Please configure at least one integration with 'cli_cmd'.",
			vim.log.levels.WARN
		)
	end

	-- Create user command to open CLI tool
	vim.api.nvim_create_user_command("CLIIntegration", function(opts)
		-- Validate integrations before executing
		local integrations = config.options.integrations or {}
		if not integrations or #integrations == 0 then
			vim.notify(
				"cli-integration.nvim: No integrations configured. Please configure at least one integration with 'cli_cmd'.",
				vim.log.levels.ERROR
			)
			return
		end

		local args = opts.args

		-- Execute command with error handling
		local ok, err = pcall(function()
			if args == "open_cwd" or args == "" or not args then
				commands.open_cwd()
			elseif args == "open_root" then
				commands.open_git_root()
			else
				commands.open_custom(args, true)
			end
		end)

		if not ok then
			vim.notify("cli-integration.nvim: Error executing command: " .. tostring(err), vim.log.levels.ERROR)
		end
	end, {
		nargs = "?",
		complete = function()
			return { "open_cwd", "open_root" }
		end,
		desc = "Open CLI Integration",
	})

	-- Setup autocommands
	autocmds.setup(configs)
end

return M
