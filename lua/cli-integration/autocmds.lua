--- Autocommands module
local keymaps = require("cli-integration.keymaps")
local help = require("cli-integration.help")
local debug = require("cli-integration.debug")
local config = require("cli-integration.config")

local M = {}

--- Setup autocommands for CLI Integration
--- @param user_config Cli-Integration.Config
--- @return nil
function M.setup(user_config)
	local integrations = user_config.integrations or {}
	if not integrations or #integrations == 0 then
		return
	end

	local cli_integration_group = vim.api.nvim_create_augroup("CLI-Integration", { clear = true })
	local cli_integration_opens_group = vim.api.nvim_create_augroup("CLI-Integration-Opens", { clear = true })

	local integrations_by_name = {}
	for _, integration in ipairs(integrations) do
		if integration.name and integration.name ~= "" then
			integrations_by_name[integration.name] = integration
		end
	end

	-- Use b:cli_integration_name to identify which integration a terminal belongs to.
	-- This avoids pattern matching on buffer names (which Neovim overwrites during termopen).
	vim.api.nvim_create_autocmd({ "TermOpen", "TermEnter" }, {
		group = cli_integration_group,
		pattern = "*",
		callback = function(args)
			local buf = args.buf
			local ok_var, integration_name = pcall(vim.api.nvim_buf_get_var, buf, "cli_integration_name")
			if config.options.debug then
				debug.log("autocmd_term_event", function()
					return { event = args.event, name = integration_name or "unknown", buf = buf }
				end)
			end
			if not ok_var or not integration_name then
				return
			end

			local integration = integrations_by_name[integration_name]
			if integration then
				local ok, err = pcall(keymaps.setup_terminal_keymaps, integration)
				if not ok then
					vim.notify(
						"cli-integration.nvim: Error setting up keymaps for "
							.. integration_name
							.. ": "
							.. tostring(err),
						vim.log.levels.ERROR
					)
				end
			end
		end,
	})

	local help_names = {}
	for _, integration in ipairs(integrations) do
		if integration.show_help_on_open and integration.name then
			help_names[integration.name] = true
		end
	end

	if next(help_names) then
		vim.api.nvim_create_autocmd("TermOpen", {
			group = cli_integration_opens_group,
			pattern = "*",
			callback = function(args)
				local buf = args.buf
				local ok_var, integration_name = pcall(vim.api.nvim_buf_get_var, buf, "cli_integration_name")
				if not ok_var or not integration_name then
					return
				end

				if help_names[integration_name] then
					vim.defer_fn(function()
						local ok, err = pcall(help.show_quick_help)
						if not ok then
							vim.notify(
								"cli-integration.nvim: Error showing help for "
									.. integration_name
									.. ": "
									.. tostring(err),
								vim.log.levels.ERROR
							)
						end
					end, 300)
				end
			end,
		})
	end
end

return M
