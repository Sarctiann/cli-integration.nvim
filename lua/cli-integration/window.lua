--- Window and terminal management using native Neovim API
--- This module replaces Snacks.nvim dependency
local M = {}

--- Terminal object that mimics Snacks.terminal interface
--- @class TerminalWindow
--- @field buf number Buffer number
--- @field win number|nil Window number
--- @field job_id number Job ID
--- @field cmd string Command being run
--- @field opts table Terminal options
--- @field on_close function|nil Callback when terminal closes

--- Create a new terminal window
--- @param cmd string Command to run in terminal
--- @param opts table Options for terminal creation
--- @return TerminalWindow|nil
function M.create_terminal(cmd, opts)
	opts = opts or {}
	local win_opts = opts.win or {}
	local cwd = opts.cwd or vim.fn.getcwd()
	local auto_close = opts.auto_close ~= false
	local start_insert = opts.start_insert ~= false

	-- Create a new buffer for the terminal
	local buf = vim.api.nvim_create_buf(false, true)
	if not buf or buf == 0 then
		return nil
	end

	-- Set buffer options (using vim.bo to avoid deprecation warnings)
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].buflisted = false

	-- Create window based on position
	local position = win_opts.position or "right"
	local win = M.create_window(buf, position, win_opts)

	if not win then
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	-- Set window options (using vim.wo to avoid deprecation warnings)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].spell = false
	-- Set winhighlight to match theme panels (like neo-tree, Snacks.terminal)
	vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"

	-- Start terminal in the buffer
	local job_id
	vim.api.nvim_win_call(win, function()
		-- Change to the specified directory
		local original_cwd = vim.fn.getcwd()
		if cwd and cwd ~= "" then
			vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
		end

		-- Start the terminal (use jobstart for Neovim >= 0.11, termopen for older versions)
		-- vim.fn.termopen is deprecated in Neovim >= 0.11
		local use_jobstart = vim.fn.has("nvim-0.11") == 1
		local job_opts = {
			on_exit = function(_, exit_code, _)
				if auto_close and exit_code == 0 then
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(buf) then
							vim.api.nvim_buf_delete(buf, { force = true })
						end
					end)
				end
				if win_opts.on_close then
					vim.schedule(win_opts.on_close)
				end
			end,
		}

		if use_jobstart then
			-- jobstart requires term = true to create a terminal buffer
			job_opts.term = true
			job_id = vim.fn.jobstart(cmd, job_opts)
		else
			-- termopen is the traditional way for older versions
			---@diagnostic disable-next-line: deprecated
			job_id = vim.fn.termopen(cmd, job_opts)
		end

		-- Restore original directory
		vim.cmd("lcd " .. vim.fn.fnameescape(original_cwd))
	end)

	if not job_id or job_id <= 0 then
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	-- Set up terminal buffer keymaps for window navigation (C-h/j/k/l)
	local opts_keymap = { buffer = buf, noremap = true, silent = true }
	vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], opts_keymap)
	vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], opts_keymap)
	vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], opts_keymap)
	vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]], opts_keymap)

	-- Auto-enter insert mode when focusing the terminal window
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		buffer = buf,
		callback = function()
			-- Only enter insert mode if we're in a terminal buffer
			if vim.bo.buftype == "terminal" then
				vim.cmd("startinsert")
			end
		end,
		desc = "Auto-enter insert mode in terminal",
	})

	-- Enter insert mode if requested
	if start_insert then
		vim.cmd("startinsert")
	end

	-- Create terminal object
	local terminal = {
		buf = buf,
		win = win,
		job_id = job_id,
		cmd = cmd,
		opts = opts,
		on_close = win_opts.on_close,
	}

	-- Add toggle method
	terminal.toggle = function()
		M.toggle_terminal(terminal)
	end

	return terminal
end

--- Create a window for the buffer
--- @param buf number Buffer number
--- @param position string Window position ("float", "right", "bottom")
--- @param win_opts table Window options
--- @return number|nil Window number
function M.create_window(buf, position, win_opts)
	if position == "float" then
		return M.create_float_window(buf, win_opts)
	elseif position == "bottom" then
		return M.create_split_window(buf, "bottom", win_opts)
	else
		-- Default to right split
		return M.create_split_window(buf, "right", win_opts)
	end
end

--- Create a floating window
--- @param buf number Buffer number
--- @param win_opts table Window options
--- @return number|nil Window number
function M.create_float_window(buf, win_opts)
	local width = win_opts.width or math.floor(vim.o.columns * 0.8)
	local height = win_opts.height or math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = win_opts.border or "rounded",
		title = win_opts.title or "",
		title_pos = "center",
	}

	return vim.api.nvim_open_win(buf, true, opts)
end

--- Create a split window
--- @param buf number Buffer number
--- @param direction string Split direction ("right" or "bottom")
--- @param win_opts table Window options
--- @return number|nil Window number
function M.create_split_window(buf, direction, win_opts)
	local cmd
	if direction == "bottom" then
		cmd = "botright split"
	else
		cmd = "botright vsplit"
	end

	vim.cmd(cmd)
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Set window width/height
	if direction == "right" then
		-- Support percentage (0-100) - values <= 100 are treated as percentage
		-- Values > 100 are treated as absolute character width (for very wide terminals)
		local width_config = win_opts.min_width or win_opts.width or 34
		local width
		local editor_width = vim.o.columns

		if width_config <= 100 then
			-- Percentage mode: treat as percentage (e.g., 34 = 34%, 0.34 = 0.34%)
			local percentage = width_config <= 1 and width_config or (width_config / 100)

			-- Validate percentage range (10% - 90%)
			if percentage < 0.10 then
				vim.notify(
					"[cli-integration] window_width must be between 10% and 90%. Using minimum 10%.",
					vim.log.levels.WARN
				)
				percentage = 0.10
			elseif percentage > 0.90 then
				vim.notify(
					"[cli-integration] window_width must be between 10% and 90%. Using maximum 90%.",
					vim.log.levels.WARN
				)
				percentage = 0.90
			end

			width = math.floor(editor_width * percentage)
		else
			-- Absolute mode: use the value directly (for very wide terminals)
			width = width_config
		end

		vim.api.nvim_win_set_width(win, width)
		-- Prevent window from being resized automatically
		vim.wo[win].winfixwidth = true
	elseif direction == "bottom" then
		local height = win_opts.height or 15
		vim.api.nvim_win_set_height(win, height)
		vim.wo[win].winfixheight = true
	end

	-- Set winhighlight to match theme panels
	vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"

	return win
end

--- Toggle terminal window visibility
--- @param terminal TerminalWindow Terminal object
--- @return nil
function M.toggle_terminal(terminal)
	if not terminal or not terminal.buf or not vim.api.nvim_buf_is_valid(terminal.buf) then
		return
	end

	-- Check if window is currently visible
	local win_visible = false
	if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
		win_visible = true
	end

	if win_visible then
		-- Hide the window
		vim.api.nvim_win_close(terminal.win, false)
		terminal.win = nil
	else
		-- Show the window
		local position = terminal.opts.win and terminal.opts.win.position or "right"
		local win_opts = terminal.opts.win or {}
		local win = M.create_window(terminal.buf, position, win_opts)

		if win then
			terminal.win = win
			-- Enter insert mode if auto_insert is enabled
			if terminal.opts.auto_insert ~= false then
				vim.cmd("startinsert")
			end
		end
	end
end

--- Check if a terminal window is visible
--- @param terminal TerminalWindow Terminal object
--- @return boolean
function M.is_terminal_visible(terminal)
	if not terminal or not terminal.win then
		return false
	end
	return vim.api.nvim_win_is_valid(terminal.win)
end

return M
