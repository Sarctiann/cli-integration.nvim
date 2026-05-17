--- Ask hook module — captures context, shows input, sends to terminal
local M = {}

--- Capture current editing context (file, cursor, visual selection)
--- Must be called BEFORE any window/mode changes.
--- @param screen_capture table|nil {row, col} to store screen position into (optional)
--- @return Cli-Integration.AskData
local function capture_context(screen_capture)
	-- Capture screen position first, before anything changes
	if screen_capture then
		screen_capture.row = vim.fn.screenrow()
		screen_capture.col = vim.fn.screencol()
	end

	local file = vim.fn.expand("%:p")
	local relative_file = vim.fn.expand("%")
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1]
	local filetype = vim.bo.filetype

	local mode = vim.api.nvim_get_mode().mode
	local selection = nil
	local start_line = cursor_line
	local end_line = cursor_line

	if mode:match("[vV\22]") then
		-- Visual mode: capture selection from marks '< and '>
		local start_pos = vim.fn.getpos("'<")
		local end_pos = vim.fn.getpos("'>")
		start_line = start_pos[2]
		end_line = end_pos[2]

		local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
		selection = table.concat(lines, "\n")

		-- Exit visual mode synchronously so we can open a floating window
		vim.api.nvim_input("<Esc>")
	end

	return {
		file = file,
		relative_file = relative_file,
		start_line = start_line,
		end_line = end_line,
		selection = selection,
		filetype = filetype,
	}
end

--- Show a floating input window near the cursor
--- @param title string Window title
--- @param screen_row number 1-indexed screen row (from screenrow())
--- @param screen_col number 1-indexed screen col (from screencol())
--- @param on_submit fun(text: string) Called with trimmed text when user presses Enter
--- @param on_cancel fun() Called when user presses Escape or cancels
local function show_input(title, screen_row, screen_col, on_submit, on_cancel)
	-- Convert to 0-indexed for nvim_open_win
	local sr = screen_row - 1
	local sc = screen_col - 1

	local width = math.min(60, vim.o.columns - 4)
	local height = 3

	-- Position below cursor, centered horizontally
	local row = sr + 1
	local col = sc - math.floor(width / 2)

	-- Clamp horizontal
	col = math.max(0, math.min(col, vim.o.columns - width))

	-- Clamp vertical: if off-screen at bottom, place above cursor
	if row + height > vim.o.lines - 1 then
		row = sr - height - 1
		row = math.max(0, row)
	end

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"

	-- Create floating window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
		style = "minimal",
	})

	-- Guard against double-submit
	local submitted = false

	-- Buffer-local keymaps
	local opts = { buffer = buf, nowait = true, silent = true }

	vim.keymap.set("i", "<CR>", function()
		if submitted then return end
		submitted = true
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local text = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
		pcall(vim.api.nvim_win_close, win, true)
		if text ~= "" then
			on_submit(text)
		else
			on_cancel()
		end
	end, opts)

	vim.keymap.set("i", "<Esc>", function()
		pcall(vim.api.nvim_win_close, win, true)
		on_cancel()
	end, opts)

	vim.keymap.set("n", "<Esc>", function()
		pcall(vim.api.nvim_win_close, win, true)
		on_cancel()
	end, opts)

	-- Focus and enter insert mode
	vim.api.nvim_set_current_win(win)
	vim.cmd("startinsert!")
end

--- Look up integration by name, index, or cli_cmd (same logic as commands.lua)
--- @param identifier string|number|nil
--- @return Cli-Integration.Integration|nil
--- @return string|nil error message
local function lookup_integration(identifier)
	local config = require("cli-integration.config")
	local integrations = config.options.integrations or {}

	if not integrations or #integrations == 0 then
		return nil, "No integrations configured. Please configure at least one integration with 'cli_cmd'."
	end

	if not identifier then
		return integrations[1], nil
	end

	if type(identifier) == "number" then
		if identifier < 1 or identifier > #integrations then
			return nil, "Integration index " .. identifier .. " is out of range (1-" .. #integrations .. ")"
		end
		return integrations[identifier], nil
	elseif type(identifier) == "string" then
		local normalized = identifier:gsub("_", " ")
		for _, integration in ipairs(integrations) do
			if integration.name == normalized or integration.name == identifier then
				return integration, nil
			end
		end
		for _, integration in ipairs(integrations) do
			if integration.cli_cmd == identifier then
				return integration, nil
			end
		end
		return nil, "Integration with name or cli_cmd '" .. identifier .. "' not found"
	end

	return nil, "Invalid identifier type"
end

--- Send formatted text to a terminal and auto-submit
--- @param term_buf number Terminal buffer handle
--- @param text string Text to insert
local function send_to_terminal(term_buf, text)
	local terminal = require("cli-integration.terminal")

	-- Insert the formatted question text
	terminal.insert_text(text, term_buf)

	-- Auto-submit: send Enter
	local job_id = terminal.get_terminal_job_id(term_buf)
	if job_id and vim.fn.jobwait({ job_id }, 10)[1] == -1 then
		vim.fn.chansend(job_id, "\r")
	end

	-- Focus the terminal window so user sees the response
	terminal.focus_terminal_window(term_buf)
end

--- Ensure the terminal exists and is visible, then call on_ready with term_data.
--- For closed integrations: opens the terminal (suppressing start_with_text), waits
--- for CLI readiness via the existing attach_text_when_ready polling, then proceeds.
--- @param integration Cli-Integration.Integration
--- @param on_ready fun(term_data: table) Called when terminal is ready
local function ensure_terminal_ready(integration, on_ready)
	local terminal = require("cli-integration.terminal")
	local name = integration.name
	local term_data = terminal.terminals[name]

	if term_data and term_data.term_buf and vim.api.nvim_buf_is_valid(term_data.term_buf) then
		-- Terminal exists. If hidden, show it via toggle.
		local term_win = terminal.find_terminal_window(term_data.term_buf)
		if not term_win then
			if term_data.cli_term and term_data.cli_term.toggle then
				term_data.cli_term:toggle()
			end
		end
		on_ready(term_data)
	else
		-- Terminal doesn't exist. Open it, suppressing start_with_text so
		-- the ask hook's formatted question takes priority.
		local saved_start = integration.start_with_text
		integration.start_with_text = function()
			-- CLI is ready. Restore original and signal.
			integration.start_with_text = saved_start
			local fresh_data = terminal.terminals[name]
			if fresh_data then
				on_ready(fresh_data)
			end
			return "" -- don't insert anything
		end

		local working_dir = vim.fn.expand("%:p:h")
		if working_dir == "" then
			working_dir = vim.fn.getcwd()
		end

		terminal.open_terminal(integration, nil, integration.keep_open, working_dir)
	end
end

--- Ask a question to a CLI integration.
--- Captures current file context (and visual selection if in visual mode),
--- shows a floating input at cursor position, formats the question via
--- integration.format_ask_query, and sends it to the integration terminal.
--- @param integration_identifier string|number|nil Integration name, index, or cli_cmd (defaults to first)
function M.ask(integration_identifier)
	-- Step 1: Capture screen position BEFORE any mode/window changes
	local screen_cap = {}
	local context = capture_context(screen_cap)

	-- Step 2: Look up the integration
	local integration, err = lookup_integration(integration_identifier)
	if not integration then
		vim.notify("cli-integration.nvim: " .. (err or "integration not found"), vim.log.levels.WARN)
		return
	end

	-- Step 3: Ensure terminal is ready, then show input
	ensure_terminal_ready(integration, function(term_data)
		local title = integration.ask_title or integration.name
		show_input(title, screen_cap.row, screen_cap.col, function(question)
			-- User submitted: format and send
			context.question = question

			local format_ask = integration.format_ask_query
			local formatted
			if format_ask and type(format_ask) == "function" then
				local ok, result = pcall(format_ask, context, integration)
				if not ok then
					vim.notify("cli-integration.nvim: format_ask_query error: " .. tostring(result), vim.log.levels.ERROR)
					return
				end
				if type(result) ~= "string" then
					vim.notify("cli-integration.nvim: format_ask_query must return a string", vim.log.levels.ERROR)
					return
				end
				formatted = result
			else
				-- Use default formatter from config
				local config = require("cli-integration.config")
				local default_fmt = config.options.format_ask_query
				formatted = default_fmt(context, integration)
			end

			if formatted and formatted ~= "" then
				send_to_terminal(term_data.term_buf, formatted)
			end
		end, function()
			-- User cancelled: nothing to do
		end)
	end)
end

return M
