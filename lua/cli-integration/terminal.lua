--- Terminal management module
local M = {}
local window = require("cli-integration.window")

-- Terminals storage: indexed by cli_cmd
-- Each entry contains: { cli_term, term_buf, working_dir, current_file, is_expanded, integration }
M.terminals = {}

-- Index for fast lookup: term_buf -> cli_cmd
M.buf_to_cli_cmd = {}

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
--- @param visual_text string|nil Optional text from visual selection (passed to start_with_text function if it's a function)
--- @return nil
function M.attach_text_when_ready(integration, term_buf, tries, visual_text)
	vim.defer_fn(function()
		tries = tries or 0
		local max_tries = 30

		if tries >= max_tries or not term_buf then
			return
		end

		if not vim.api.nvim_buf_is_valid(term_buf) then
			return
		end

		-- Determine what flag to search for and where
		local ready_flags = integration.cli_ready_flags or {}
		local search_flag = (ready_flags.search_for and ready_flags.search_for ~= "") and ready_flags.search_for
			or integration.cli_cmd
			or ""
		local from_line = ready_flags.from_line or 1
		local lines_amt = ready_flags.lines_amt or 5

		-- Search for the flag in the specified line range
		local start_line = math.max(0, from_line - 1)
		local end_line = start_line + lines_amt
		local buf_lines = vim.api.nvim_buf_get_lines(term_buf, start_line, end_line, false)

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
			-- Terminal is ready, now evaluate start_with_text (only once, when ready)
			---@type string|nil
			local text_to_insert = nil

			local start_with_text = integration.start_with_text
			if start_with_text ~= nil then
				if type(start_with_text) == "function" then
					-- Call the function with visual_text and integration as parameters
					local ok, result = pcall(start_with_text, visual_text, integration)
					if ok and type(result) == "string" then
						text_to_insert = result
					elseif ok then
						vim.notify(
							"cli-integration.nvim: start_with_text function must return a string, got " .. type(result),
							vim.log.levels.ERROR
						)
						return
					else
						vim.notify(
							"cli-integration.nvim: Error in start_with_text function: " .. tostring(result),
							vim.log.levels.ERROR
						)
						return
					end
				elseif type(start_with_text) == "string" then
					-- If start_with_text is a string, use it only if there's no visual_text
					text_to_insert = visual_text or start_with_text
				else
					vim.notify(
						"cli-integration.nvim: start_with_text must be a string or function, got "
							.. type(start_with_text),
						vim.log.levels.WARN
					)
				end
			elseif visual_text then
				-- If no start_with_text but there's visual_text, use it
				text_to_insert = visual_text
			end

			-- Insert text if available
			if text_to_insert and text_to_insert ~= "" then
				M.insert_text(text_to_insert, term_buf)
			end
			return
		end

		-- Terminal not ready yet, retry
		M.attach_text_when_ready(integration, term_buf, tries + 1, visual_text)
	end, 500)
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
	vim.notify(help_text, vim.log.levels.WARN)
end

--- Open or toggle the CLI tool terminal
--- @param integration Cli-Integration.Integration The integration configuration
--- @param args string|nil Command line arguments for CLI tool
--- @param keep_open boolean|nil Whether to keep the terminal open after execution
--- @param working_dir string|nil Working directory for the terminal
--- @param visual_text string|nil Optional text from visual selection (overrides start_with_text)
--- @return nil
function M.open_terminal(integration, args, keep_open, working_dir, visual_text)
	if not integration or not integration.cli_cmd or integration.cli_cmd == "" then
		show_config_help()
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

	local cli_term = window.create_terminal(cli_cmd .. cmd, {
		interactive = true,
		cwd = base_dir,
		win = {
			title = " " .. integration.name .. " " .. (args and " ( " .. args .. " ) " or ""),
			position = integration.floating and "float" or "right",
			min_width = integration.floating and nil or integration.window_width,
			padding = integration.window_padding or 0,
			border = integration.border,
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

	-- Attach text if new terminal (only if visual_text or start_with_text is set)
	local start_with_text = integration.start_with_text
	if
		visual_text
		or (start_with_text ~= nil and (type(start_with_text) == "string" or type(start_with_text) == "function"))
	then
		M.attach_text_when_ready(integration, term_buf, nil, visual_text)
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

	local width_config = integration.window_width or 34
	local editor_width = vim.o.columns
	local default_width

	-- Calculate default width using the same logic as create_split_window
	if width_config <= 100 then
		-- Percentage mode: treat as percentage (e.g., 34 = 34%, 0.34 = 0.34%)
		local percentage = width_config <= 1 and width_config or (width_config / 100)

		-- Validate percentage range (10% - 90%)
		if percentage < 0.10 then
			percentage = 0.10
		elseif percentage > 0.90 then
			percentage = 0.90
		end

		default_width = math.floor(editor_width * percentage)
	else
		-- Absolute mode: use the value directly (for very wide terminals)
		default_width = width_config
	end

	local is_expanded = not term_data.is_expanded

	-- Handle sidebar mode if applicable
	if window.sidebars[term_win] then
		window.update_sidebar_geometry(term_win, is_expanded, true)
	else
		-- Normal split window logic
		local width
		if is_expanded then
			width = editor_width - 2
		else
			width = default_width
		end
		vim.api.nvim_win_set_width(term_win, width)
	end

	term_data.is_expanded = is_expanded
end

--- Hide terminal window (keeps process alive)
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.hide_terminal(term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return
	end

	local cli_cmd = M.buf_to_cli_cmd[term_buf]
	local term_data = cli_cmd and M.terminals[cli_cmd]

	if not term_data or not term_data.cli_term then
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

	if term_win and vim.api.nvim_win_is_valid(term_win) then
		vim.api.nvim_win_close(term_win, false)
	end
end

--- Close terminal window and kill the process
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.close_terminal(term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return
	end

	local cli_cmd = M.buf_to_cli_cmd[term_buf]
	local term_data = cli_cmd and M.terminals[cli_cmd]

	if not term_data or not term_data.cli_term then
		-- If we don't have term_data, just try to close the window and delete the buffer
		local term_win = nil
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == term_buf then
				term_win = win
				break
			end
		end

		if term_win and vim.api.nvim_win_is_valid(term_win) then
			vim.api.nvim_win_close(term_win, true)
		end

		if vim.api.nvim_buf_is_valid(term_buf) then
			-- Try to get job_id and stop it
			local ok, job_id = pcall(vim.api.nvim_buf_get_var, term_buf, "terminal_job_id")
			if ok and job_id then
				vim.fn.jobstop(job_id)
			end
			vim.api.nvim_buf_delete(term_buf, { force = true })
		end
		return
	end

	-- Get job_id from the terminal
	local job_id = term_data.cli_term.job_id

	-- Close the window first
	local term_win = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == term_buf then
			term_win = win
			break
		end
	end

	if term_win and vim.api.nvim_win_is_valid(term_win) then
		vim.api.nvim_win_close(term_win, true)
	end

	-- Stop the job/process
	if job_id and job_id > 0 then
		vim.fn.jobstop(job_id)
	end

	-- Delete the buffer
	if vim.api.nvim_buf_is_valid(term_buf) then
		vim.api.nvim_buf_delete(term_buf, { force = true })
	end

	-- Clean up terminal data (the on_close callback should handle this, but just in case)
	M.terminals[cli_cmd] = nil
	M.buf_to_cli_cmd[term_buf] = nil
end

return M
