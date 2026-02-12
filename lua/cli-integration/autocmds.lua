--- Autocommands module
local keymaps = require("cli-integration.keymaps")
local help = require("cli-integration.help")

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

	-- Setup autocommands for each integration
	for _, integration in ipairs(integrations) do
		local cli_cmd = integration.cli_cmd or ""
		if cli_cmd == "" or type(cli_cmd) ~= "string" then
			goto continue
		end

		-- Validate cli_cmd is not too short to avoid false matches
		if #cli_cmd < 2 then
			vim.notify(
				"cli-integration.nvim: cli_cmd '" .. cli_cmd .. "' is too short (minimum 2 characters recommended)",
				vim.log.levels.WARN
			)
		end

		-- Setup keymaps when terminal opens or is entered
		-- Pattern matches any terminal with the CLI command name
		-- Wrap callback in error handler
		vim.api.nvim_create_autocmd({ "TermOpen", "TermEnter" }, {
			group = cli_integration_group,
			pattern = "term://*" .. vim.fn.escape(cli_cmd, "*") .. "*",
			callback = function()
				local ok, err = pcall(keymaps.setup_terminal_keymaps)
				if not ok then
					vim.notify(
						"cli-integration.nvim: Error setting up keymaps for " .. cli_cmd .. ": " .. tostring(err),
						vim.log.levels.ERROR
					)
				end
			end,
		})

		-- Show help notification when opening the terminal
		if integration.show_help_on_open then
			vim.api.nvim_create_autocmd("TermOpen", {
				group = cli_integration_opens_group,
				pattern = "term://*" .. vim.fn.escape(cli_cmd, "*") .. "*",
				callback = function()
					local ok, err = pcall(help.show_quick_help)
					if not ok then
						vim.notify(
							"cli-integration.nvim: Error showing help for " .. cli_cmd .. ": " .. tostring(err),
							vim.log.levels.ERROR
						)
					end
				end,
			})
		end

		::continue::
	end
end

return M
