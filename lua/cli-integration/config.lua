--- @class Cli-Integration.TerminalModeKeys
--- @field normal_mode string[]|nil # Keys to enter normal mode
--- @field insert_file_path string[]|nil # Keys to insert current file path
--- @field insert_all_buffers string[]|nil # Keys to insert all open buffer paths
--- @field new_lines string[]|nil # Keys to insert new lines
--- @field submit string[]|nil # Keys to submit command/message
--- @field enter string[]|nil # Keys to send Enter key
--- @field help string[]|nil # Keys to show help
--- @field toggle_width string[]|nil # Keys to toggle window width
--- @field hide string[]|nil # Keys to hide terminal (keeps process alive)
--- @field close string[]|nil # Keys to close the terminal window and kill process

--- @class Cli-Integration.NormalModeKeys
--- @field hide string[]|nil # Keys to hide terminal (keeps process alive)
--- @field toggle_width string[]|nil # Keys to toggle window width
--- @field close string[]|nil # Keys to close the terminal window and kill process

--- @class Cli-Integration.TerminalKeys
--- @field terminal_mode Cli-Integration.TerminalModeKeys|nil # Key mappings for terminal mode
--- @field normal_mode Cli-Integration.NormalModeKeys|nil # Key mappings for normal mode

--- @class Cli-Integration.CliReadyFlags
--- @field search_for string # Text to search for to detect readiness
--- @field from_line number|nil # Starting line to inspect (1-based)
--- @field lines_amt number|nil # Number of lines to inspect

--- @class Cli-Integration.Integration
--- @field cli_cmd string # CLI command name to execute (required)
--- @field name string # Name for the integration (required, used for autocompletion in commands)
--- @field show_help_on_open boolean|nil # Whether to show help notification when opening the terminal (default: true)
--- @field new_lines_amount number|nil # Number of new lines to insert after command submission (default: 2)
--- @field window_width number|nil # Default width for the terminal window (default: 34, percentage 0-100 or absolute value >100)
--- @field window_padding number|nil # Horizontal padding in columns (default: 0, adds empty space on left and right)
--- @field border string|nil # Border style for terminal window: "none", "single", "double", "rounded", "solid", "shadow" (default: "none" for sidebar, "rounded" for floating and when expanded)
--- @field floating boolean|nil # Whether to open terminal in floating window (default: false)
--- @field keep_open boolean|nil # Whether to keep the terminal open after execution (default: false)
--- @field start_with_text string|(fun(visual_text: string|nil, integration: Cli-Integration.Integration|nil): string)|nil # Text to insert when terminal is ready, or function that receives visual_text and returns text to insert (if not set, no text is inserted)
--- @field cli_ready_flags Cli-Integration.CliReadyFlags|nil # Configuration for detecting when the CLI tool is ready
--- @field format_paths (fun(path: string): string)|nil # Function to format file paths when inserting (if not set, uses the raw path)
--- @field terminal_keys Cli-Integration.TerminalKeys|nil # Key mappings for the CLI terminal window (all values must be arrays)
--- @field open_delay number|nil # Milliseconds to wait before creating the terminal window (default: 0, no delay). Useful when an on_open hook triggers an external process that needs time to start.
--- @field on_open (fun(integration: Cli-Integration.Integration, working_dir: string): nil)|nil # Called before the terminal is created. Use it for pre-launch setup (e.g., writing config files with dynamic values like the Neovim socket path).
--- @field on_close (fun(integration: Cli-Integration.Integration, working_dir: string): nil)|nil # Called after the terminal process exits. Use it for cleanup tasks (e.g., removing temporary config files).
--- @field start_insert_on_click boolean|nil # In normal mode, clicking inside the terminal window re-enters insert mode. Has no effect when clicking from another window (WinEnter already handles that). (default: false)
--- @field list_buffer boolean|nil # Show the terminal buffer in bufferline with name "[integration.name]". Sidebar windows start 1 row lower to avoid overlapping bufferline. Row offset does not apply to floating windows. (default: false)
--- @field env table<string, string>|nil # Environment variable overrides passed to the terminal job. Merged on top of inherited environment.
--- @field unset_env string[]|nil # Environment variable names to remove from the terminal job environment after merging.

--- @class Cli-Integration.Config
--- @field integrations Cli-Integration.Integration[]|nil # Array of CLI integrations (optional, defaults to empty array)
--- @field show_help_on_open boolean|nil # Default: whether to show help notification when opening the terminal (applied to all integrations)
--- @field new_lines_amount number|nil # Default: number of new lines to insert after command submission (applied to all integrations)
--- @field window_width number|nil # Default: width for the terminal window (percentage 0-100 or absolute value >100, applied to all integrations)
--- @field window_padding number|nil # Default: horizontal padding in columns (applied to all integrations)
--- @field border string|nil # Default: border style for terminal window (applied to all integrations)
--- @field floating boolean|nil # Default: whether to open terminal in floating window (applied to all integrations)
--- @field terminal_keys Cli-Integration.TerminalKeys|nil # Default: key mappings for the CLI terminal window (applied to all integrations)
--- @field start_insert_on_click boolean|nil # Default: force insert mode on click (applied to all integrations)
--- @field list_buffer boolean|nil # Default: show terminal buffer in bufferline (applied to all integrations)
--- @field env table<string, string>|nil # Default: environment variable overrides passed to all integration jobs
--- @field unset_env string[]|nil # Default: environment variable names removed from all integration jobs

local M = {}

--- Default configuration (applied to all integrations unless overridden)
M.defaults = {
	integrations = {},
	show_help_on_open = true,
	new_lines_amount = 2,
	window_width = 34, -- 34% of editor width
	window_padding = 0, -- No padding by default
	border = "none", -- No border by default for sidebar (rounded when expanded or floating)
	floating = false,
	start_insert_on_click = false,
	list_buffer = false,
	env = {},
	unset_env = {},
	terminal_keys = {
		terminal_mode = {
			normal_mode = { "<M-q>" },
			insert_file_path = { "<C-p>" },
			insert_all_buffers = { "<C-p><C-p>" },
			new_lines = { "<S-CR>" },
			submit = { "<C-s>", "<C-CR>" },
			enter = { "<CR>" },
			help = { "<M-?>", "??", "\\\\" },
			toggle_width = { "<C-f>" },
			hide = { "<C-q>" },
			close = { "<C-S-q>" },
		},
		normal_mode = {
      toggle_width = { "<C-f>" },
			hide = { "<C-q>" },
			close = { "<C-S-q>" },
		},
	},
}

--- Current configuration
M.options = {}

--- Validate that terminal_keys structure is correct (all values must be arrays)
--- @param terminal_keys table|nil
--- @return boolean
local function validate_terminal_keys(terminal_keys)
	if not terminal_keys then
		return true
	end

	local function validate_keys_table(keys_table)
		if type(keys_table) ~= "table" then
			return false
		end
		for _, value in pairs(keys_table) do
			if type(value) == "table" then
				-- Check if it's an array (all keys are numeric)
				local is_array = true
				for k, _ in pairs(value) do
					if type(k) ~= "number" then
						is_array = false
						break
					end
				end
				if not is_array then
					-- It's a nested table, recurse
					if not validate_keys_table(value) then
						return false
					end
				end
			else
				-- Non-table values should not exist in terminal_keys
				return false
			end
		end
		return true
	end

	return validate_keys_table(terminal_keys)
end

--- Validate env table structure (string keys and string values)
--- @param env table|nil
--- @return boolean
local function validate_env(env)
	if env == nil then
		return true
	end

	if type(env) ~= "table" then
		return false
	end

	for key, value in pairs(env) do
		if type(key) ~= "string" or type(value) ~= "string" then
			return false
		end
	end

	return true
end

--- Validate unset_env structure (array of strings)
--- @param unset_env table|nil
--- @return boolean
local function validate_unset_env(unset_env)
	if unset_env == nil then
		return true
	end

	if type(unset_env) ~= "table" then
		return false
	end

	for index, key in pairs(unset_env) do
		if type(index) ~= "number" or type(key) ~= "string" then
			return false
		end
	end

	return true
end

--- @param config Cli-Integration.Config
--- @return Cli-Integration.Config
function M.setup(config)
	local user_config = config or {}

	-- Validate integrations is a table if provided
	if user_config.integrations ~= nil and type(user_config.integrations) ~= "table" then
		vim.notify(
			"cli-integration.nvim: 'integrations' must be a table/array",
			vim.log.levels.ERROR
		)
		user_config.integrations = {}
	end

	M.options = vim.tbl_deep_extend("force", M.defaults, user_config)

	-- Validate global terminal_keys if provided
	if user_config.terminal_keys and not validate_terminal_keys(M.options.terminal_keys) then
		vim.notify(
			"cli-integration.nvim: 'terminal_keys' values must be arrays",
			vim.log.levels.WARN
		)
		M.options.terminal_keys = M.defaults.terminal_keys
	end

	-- Validate global env if provided
	if user_config.env and not validate_env(M.options.env) then
		vim.notify(
			"cli-integration.nvim: 'env' must be a table with string keys and string values",
			vim.log.levels.WARN
		)
		M.options.env = vim.deepcopy(M.defaults.env)
	end

	-- Validate global unset_env if provided
	if user_config.unset_env and not validate_unset_env(M.options.unset_env) then
		vim.notify(
			"cli-integration.nvim: 'unset_env' must be an array of strings",
			vim.log.levels.WARN
		)
		M.options.unset_env = vim.deepcopy(M.defaults.unset_env)
	end

	-- Apply global defaults to each integration (unless overridden by integration-specific config)
	if M.options.integrations then
		for i, integration in ipairs(M.options.integrations) do
			-- Validate integration is a table
			if type(integration) ~= "table" then
				vim.notify(
					"cli-integration.nvim: Integration at index " .. i .. " must be a table",
					vim.log.levels.WARN
				)
				goto continue
			end

			-- Validate cli_cmd is present and not empty
			local cli_cmd = integration.cli_cmd
			if not cli_cmd or type(cli_cmd) ~= "string" or cli_cmd == "" then
				vim.notify(
					"cli-integration.nvim: Integration at index " .. i .. " must have a non-empty 'cli_cmd'",
					vim.log.levels.WARN
				)
				goto continue
			end

			-- Validate name is present and not empty
			local name = integration.name
			if not name or type(name) ~= "string" or name == "" then
				vim.notify(
					"cli-integration.nvim: Integration at index " .. i .. " must have a non-empty 'name'",
					vim.log.levels.WARN
				)
				goto continue
			end

			-- Validate terminal_keys if provided
			if integration.terminal_keys and not validate_terminal_keys(integration.terminal_keys) then
				vim.notify(
					"cli-integration.nvim: Integration '" .. cli_cmd .. "' has invalid 'terminal_keys' (values must be arrays)",
					vim.log.levels.WARN
				)
				integration.terminal_keys = nil -- Will use global default
			end

			-- Validate env if provided
			if integration.env and not validate_env(integration.env) then
				vim.notify(
					"cli-integration.nvim: Integration '" .. cli_cmd .. "' has invalid 'env' (must be table<string, string>)",
					vim.log.levels.WARN
				)
				integration.env = nil -- Will use global default
			end

			-- Validate unset_env if provided
			if integration.unset_env and not validate_unset_env(integration.unset_env) then
				vim.notify(
					"cli-integration.nvim: Integration '"
						.. cli_cmd
						.. "' has invalid 'unset_env' (must be string[])",
					vim.log.levels.WARN
				)
				integration.unset_env = nil -- Will use global default
			end

			-- Build terminal_keys: per-section override with key-by-key merge
			-- If integration defines terminal_keys, it replaces entire sub-section (terminal_mode or normal_mode)
			-- but within each sub-section, only defined keys are overridden
			local plugin_tkeys = M.options.terminal_keys
			local int_tkeys = integration.terminal_keys
			local final_tkeys = {}

			-- terminal_mode: if integration defines it, merge with plugin; otherwise inherit
			if int_tkeys and int_tkeys.terminal_mode then
				final_tkeys.terminal_mode = vim.tbl_extend("force", plugin_tkeys.terminal_mode, int_tkeys.terminal_mode)
			else
				final_tkeys.terminal_mode = plugin_tkeys.terminal_mode
			end

			-- normal_mode: same logic
			if int_tkeys and int_tkeys.normal_mode then
				final_tkeys.normal_mode = vim.tbl_extend("force", plugin_tkeys.normal_mode, int_tkeys.normal_mode)
			else
				final_tkeys.normal_mode = plugin_tkeys.normal_mode
			end

			-- Start with global defaults
			local default_integration = {
				show_help_on_open = M.options.show_help_on_open,
				new_lines_amount = M.options.new_lines_amount,
				window_width = M.options.window_width,
				window_padding = M.options.window_padding,
				border = M.options.border,
				floating = M.options.floating,
				start_insert_on_click = M.options.start_insert_on_click,
				list_buffer = M.options.list_buffer,
				env = vim.deepcopy(M.options.env),
				unset_env = vim.deepcopy(M.options.unset_env),
				cli_ready_flags = {
					search_for = "",
					from_line = 1,
					lines_amt = 5,
				},
				terminal_keys = final_tkeys,
			}
			-- Apply integration-specific config (which may override defaults)
			-- Note: terminal_keys handled separately above, so exclude it from deep extend
			local integration_without_tkeys = vim.deepcopy(integration)
			integration_without_tkeys.terminal_keys = nil
			M.options.integrations[i] = vim.tbl_deep_extend("force", default_integration, integration_without_tkeys)
			-- Restore terminal_keys (already properly merged above)
			M.options.integrations[i].terminal_keys = final_tkeys

			::continue::
		end
	end

	return M.options
end

return M
