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

return M
