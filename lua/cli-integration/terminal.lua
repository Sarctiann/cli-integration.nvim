--- Terminal management module
local M = {}

-- Terminals storage: indexed by cli_cmd
-- Each entry contains: { cli_term, term_buf, working_dir, current_file, is_expanded, integration }
M.terminals = {}

-- Index for fast lookup: term_buf -> cli_cmd
M.buf_to_cli_cmd = {}

--- Check if Snacks is available
--- @return boolean
local function has_snacks()
	return type(_G.Snacks) == "table"
		and type(_G.Snacks.terminal) == "function"
		and type(_G.Snacks.notify) == "function"
end

--- Insert text into the terminal
--- @param text string The text to insert
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.insert_text(text, term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if term_buf then
		local job_id = vim.b.terminal_job_id or vim.api.nvim_buf_get_var(term_buf, "terminal_job_id")
		if job_id and vim.fn.jobwait({ job_id }, 10)[1] == -1 then
			vim.fn.chansend(job_id, text)
		end
	end
end

--- Get current terminal buffer from active window
--- @return number|nil
function M.get_current_terminal_buf()
	local current_buf = vim.api.nvim_get_current_buf()
	local buftype = vim.api.nvim_get_option_value("buftype", { buf = current_buf })
	if buftype == "terminal" then
		return current_buf
	end
	return nil
end

--- Get integration for a terminal buffer
--- @param term_buf number|nil The terminal buffer
--- @return Cli-Integration.Integration|nil
function M.get_integration_for_buf(term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return nil
	end

	local cli_cmd = M.buf_to_cli_cmd[term_buf]
	if cli_cmd and M.terminals[cli_cmd] then
		return M.terminals[cli_cmd].integration
	end

	return nil
end

--- Attach text to the terminal when CLI tool is ready
--- @param integration Cli-Integration.Integration The integration configuration
--- @param term_buf number The terminal buffer
--- @param tries number|nil Number of tries so far
--- @return nil
function M.attach_text_when_ready(integration, term_buf, tries)
	vim.defer_fn(function()
		tries = tries or 0
		local max_tries = 12

		if tries >= max_tries or not term_buf then
			return
		end

		if not vim.api.nvim_buf_is_valid(term_buf) then
			return
		end

		-- Determine what flag to search for
		local search_flag = integration.ready_text_flag or integration.cli_cmd or ""

		-- Get text to insert from configuration
		local text_to_insert = integration.start_with_text

		-- If no text to insert, don't do anything
		if not text_to_insert or text_to_insert == "" then
			return
		end

		-- Search for the flag in the first 10 lines
		local buf_lines = vim.api.nvim_buf_get_lines(term_buf, 0, 10, false)
		local found = false
		if search_flag and search_flag ~= "" then
			for i = 1, #buf_lines do
				if buf_lines[i] and buf_lines[i]:match(search_flag) then
					found = true
					break
				end
			end
		end

		if found then
			M.insert_text(text_to_insert, term_buf)
			return
		end

		M.attach_text_when_ready(integration, term_buf, tries + 1)
	end, 300)
end

--- Show configuration help message
local function show_config_help()
	local help_text = [[
cli-integration.nvim requires configuration.

Minimum configuration:
  require("cli-integration").setup({
    integrations = {
      { cli_cmd = "your-cli-tool" },  -- Required: specify your CLI command name
    },
  })

Example:
  require("cli-integration").setup({
    integrations = {
      { cli_cmd = "cursor-agent" },
    },
  })
]]
	if has_snacks() and _G.Snacks then
		_G.Snacks.notify(help_text, {
			title = "Configuration Required",
			style = "compact",
			history = false,
			timeout = 10000,
		})
	else
		vim.notify(help_text, vim.log.levels.WARN)
	end
end

--- Open or toggle the CLI tool terminal
--- @param integration Cli-Integration.Integration The integration configuration
--- @param args string|nil Command line arguments for CLI tool
--- @param keep_open boolean|nil Whether to keep the terminal open after execution
--- @param working_dir string|nil Working directory for the terminal
--- @return nil
function M.open_terminal(integration, args, keep_open, working_dir)
	if not integration or not integration.cli_cmd or integration.cli_cmd == "" then
		show_config_help()
		return
	end

	if not _G.Snacks then
		vim.notify("cli-integration.nvim: Snacks.nvim is required but not available", vim.log.levels.ERROR)
		return
	end

	local cli_cmd = integration.cli_cmd
	local term_data = M.terminals[cli_cmd]

	-- Toggle if terminal already exists and is valid
	if term_data and term_data.cli_term and term_data.cli_term.toggle then
		if term_data.term_buf and vim.api.nvim_buf_is_valid(term_data.term_buf) then
			term_data.cli_term:toggle()
			return
		else
			-- Terminal buffer is invalid, clean it up
			M.terminals[cli_cmd] = nil
			if term_data.term_buf then
				M.buf_to_cli_cmd[term_data.term_buf] = nil
			end
		end
	end

	-- Create new terminal
	local cmd = args and " " .. args or ""
	local current_file_abs = vim.fn.expand("%:p")
	local base_dir = working_dir or vim.fn.getcwd()
	local current_file = vim.fn.expand("%")
	if base_dir and base_dir ~= "" and current_file_abs ~= "" then
		current_file = vim.fs.relpath(base_dir, current_file_abs) or vim.fn.fnamemodify(current_file_abs, ":.")
	end

	local cli_term = _G.Snacks.terminal(cli_cmd .. cmd, {
		interactive = true,
		cwd = base_dir,
		win = {
			title = " " .. cli_cmd .. " " .. (args and " ( " .. args .. " ) " or ""),
			position = integration.floating and "float" or "right",
			min_width = integration.floating and nil or integration.window_width,
			border = "rounded",
			on_close = function()
				local stored_data = M.terminals[cli_cmd]
				M.terminals[cli_cmd] = nil
				if stored_data and stored_data.term_buf then
					M.buf_to_cli_cmd[stored_data.term_buf] = nil
				end
			end,
			resize = true,
		},
		auto_close = not keep_open,
		start_insert = not keep_open,
		auto_insert = not keep_open,
	})

	if not cli_term then
		vim.notify("cli-integration.nvim: Failed to create terminal for " .. cli_cmd, vim.log.levels.ERROR)
		return
	end

	local term_buf = cli_term.buf
	if not term_buf then
		vim.notify("cli-integration.nvim: Terminal buffer not available for " .. cli_cmd, vim.log.levels.ERROR)
		return
	end

	-- Store terminal data
	M.terminals[cli_cmd] = {
		cli_term = cli_term,
		term_buf = term_buf,
		working_dir = base_dir,
		current_file = current_file,
		is_expanded = false,
		integration = integration,
	}

	-- Update index for fast lookup
	M.buf_to_cli_cmd[term_buf] = cli_cmd

	-- Attach text if new terminal (only if start_with_text is set)
	if integration.start_with_text and integration.start_with_text ~= "" then
		M.attach_text_when_ready(integration, term_buf)
	end
end

--- Toggle terminal window width between default and maximum
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.toggle_width(term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return
	end

	local cli_cmd = M.buf_to_cli_cmd[term_buf]
	local term_data = cli_cmd and M.terminals[cli_cmd]

	if not term_data then
		return
	end

	-- Get the terminal window
	local term_win = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == term_buf then
			term_win = win
			break
		end
	end

	if not term_win or not vim.api.nvim_win_is_valid(term_win) then
		return
	end

	local integration = term_data.integration
	if not integration then
		return
	end

	local window_width = integration.window_width or 64
	local columns = vim.o.columns
	local max_width = math.max(window_width, columns - 2)

	if term_data.is_expanded then
		vim.api.nvim_win_set_width(term_win, window_width)
		term_data.is_expanded = false
	else
		vim.api.nvim_win_set_width(term_win, max_width)
		term_data.is_expanded = true
	end
end

return M
