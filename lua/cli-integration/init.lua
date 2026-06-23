--- @module 'Cli-Integration'

local config = require("cli-integration.config")
local commands = require("cli-integration.commands")
local autocmds = require("cli-integration.autocmds")
local ask = require("cli-integration.ask")
local hooks = require("cli-integration.hooks")
local debug = require("cli-integration.debug")

local M = {}

M.hooks = hooks

M.hooks.ask = ask.ask
--- Setup function for the plugin
--- @param user_config Cli-Integration.Config
--- @return nil
function M.setup(user_config)
	local configs = config.setup(user_config)

	debug.log("setup", function()
		return {
			integrations_count = #(configs.integrations or {}),
			debug_enabled = configs.debug or false,
			enable_bufferline_integration = configs.adapters and configs.adapters.bufferline or false,
			editor_columns = vim.o.columns,
			editor_lines = vim.o.lines,
			showtabline = vim.o.showtabline,
		}
	end)

	debug.setup_autocmds()

	vim.api.nvim_create_user_command("CLIIntegration", function(opts)
		local integrations = configs.integrations or {}
		if not integrations or #integrations == 0 then
			vim.notify(
				"cli-integration.nvim: No integrations configured. Please configure at least one integration with 'cli_cmd' and 'name'.",
				vim.log.levels.ERROR
			)
			return
		end

		local fargs = opts.fargs or {}
		local action = fargs[1] or ""
		local integration_name = fargs[2]

		if integration_name then
			integration_name = integration_name:gsub("_", " ")
		end

		local cli_args = nil
		if #fargs > 2 then
			local args_table = {}
			for i = 3, #fargs do
				table.insert(args_table, fargs[i])
			end
			cli_args = table.concat(args_table, " ")
		end

		local visual_text = nil
		if opts.range > 0 then
			local start_line = opts.line1
			local end_line = opts.line2
			local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
			if lines and #lines > 0 then
				visual_text = table.concat(lines, "\n") .. "\n"
			end
		end

		local ok, err = pcall(function()
			if action == "open_cwd" or action == "" or not action then
				commands.open_cwd(integration_name, cli_args, visual_text)
			elseif action == "open_root" then
				commands.open_git_root(integration_name, cli_args, visual_text)
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
				commands.open_cwd(name, backward_cli_args, visual_text)
			end
		end)

		if not ok then
			vim.notify("cli-integration.nvim: Error executing command: " .. tostring(err), vim.log.levels.ERROR)
		end
	end, {
		nargs = "*",
		range = true,
		complete = function(_, cmd_line, cursor_pos)
			local cmd_substr = cmd_line:sub(1, cursor_pos)

			cmd_substr = cmd_substr:match("^%s*(.-)%s*$") or ""

			local args = {}
			for part in cmd_substr:gmatch("%S+") do
				table.insert(args, part)
			end

			if #args > 0 and args[1] == "CLIIntegration" then
				table.remove(args, 1)
			end

			if #args == 0 then
				return { "open_cwd", "open_root" }
			end

			if args[1] == "open_cwd" or args[1] == "open_root" then
				local integrations = configs.integrations or {}
				local names = {}
				for _, integration in ipairs(integrations) do
					local display_name = integration.name:gsub(" ", "_")
					table.insert(names, display_name)
				end
				return names
			end

			if #args == 1 then
				return { "open_cwd", "open_root" }
			end

			return {}
		end,
		desc = "Open CLI Integration",
	})

	-- Setup autocommands
	autocmds.setup(configs)
end

return M
