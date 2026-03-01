--- Window and terminal management using native Neovim API
--- @class TerminalWindow
--- @field buf number Buffer number
--- @field win number|nil Window number
--- @field job_id number Job ID
--- @field cmd string Command being run
--- @field opts table Terminal options
--- @field on_close function|nil Callback when terminal closes
--- @field toggle function|nil
local M = {}

-- Store active sidebar window pairs for resizing and focus management
-- Format: [float_win] = { split_win = number, split_buf = number, terminal_buf = number, width_config = number, padding = number }
M.sidebars = {}

-- Track the last focused floating window to handle navigation correctly
M.last_focused_float = nil

-- Track if resize autocmd is setup
M.resized_autocmd_setup = false

--- Internal helper to attach focus redirection autocmds to a sidebar split
--- @param split_buf number The buffer in the split window
--- @param split_win number The split window handle
--- @param float_win number The floating terminal window handle
local function attach_sidebar_focus_logic(split_buf, split_win, float_win)
	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = split_buf,
		callback = function()
			local current_win = vim.api.nvim_get_current_win()
			if current_win == split_win then
				if M.last_focused_float == float_win then
					-- User is trying to navigate OUT of the sidebar to the left
					vim.cmd("wincmd h")
					M.last_focused_float = nil
				else
					-- User clicked or navigated INTO the split from elsewhere
					if vim.api.nvim_win_is_valid(float_win) then
						vim.api.nvim_set_current_win(float_win)
					end
				end
			end
		end,
	})
end

--- Create a new terminal window
--- @param cmd string Command to run in terminal
--- @param opts table Options for terminal creation
--- @return TerminalWindow|nil
function M.create_terminal(cmd, opts)
	opts = opts or {}
	local win_opts = opts.win or {}
	local cwd = opts.cwd or vim.fn.getcwd()
	local auto_close = opts.auto_close ~= false

	-- Create a new buffer for the terminal
	local buf = vim.api.nvim_create_buf(false, true)
	if not buf or buf == 0 then
		return nil
	end

	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].buflisted = false

	-- Determine if we are in sidebar mode or float mode
	local is_float = win_opts.position == "float"
	local win

	if is_float then
		win = M.create_float_window(buf, win_opts)
	else
		-- This is the "Sidebar" mode: split + float
		win = M.create_sidebar_layout(buf, win_opts)
	end

	if not win then
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	-- Initial focus tracking
	M.last_focused_float = win

	-- Set window options
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].spell = false

	---@type TerminalWindow
	local terminal = {
		buf = buf,
		win = win,
		job_id = 0, -- Placeholder
		cmd = cmd,
		opts = opts,
		on_close = win_opts.on_close,
	}

	terminal.toggle = function()
		M.toggle_terminal(terminal)
	end

	-- Calculate size for TUI
	local win_width = vim.api.nvim_win_get_width(win)
	local win_height = vim.api.nvim_win_get_height(win)
	local padding = win_opts.padding or 0
	local effective_width = win_width - (padding * 2)

	-- Start terminal
	local job_id
	vim.api.nvim_buf_call(buf, function()
		local original_cwd = vim.fn.getcwd()
		if cwd and cwd ~= "" then
			vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
		end

		local env = vim.tbl_extend("force", opts.env or {}, {
			COLUMNS = tostring(effective_width),
			LINES = tostring(win_height),
		})

		local use_jobstart = vim.fn.has("nvim-0.11") == 1
		local job_opts = {
			cwd = cwd,
			env = env,
			term = true,
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
			job_id = vim.fn.jobstart(cmd, job_opts)
		else
			job_opts.term = nil
			---@diagnostic disable-next-line: deprecated
			job_id = vim.fn.termopen(cmd, job_opts)
		end
		vim.cmd("lcd " .. vim.fn.fnameescape(original_cwd))
	end)

	-- Apply padding (visual spacing on left and right)
	if padding > 0 then
		-- Left padding using foldcolumn
		vim.wo[win].foldcolumn = tostring(padding)
		-- Right padding using rightleft + foldcolumn trick or signcolumn
		-- Note: For floating windows, we also need to adjust the window width
		-- to create visual right padding (handled in create_sidebar_layout)
	end

	if not job_id or job_id <= 0 then
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	terminal.job_id = job_id

	-- Navigation keymaps
	local opts_keymap = { buffer = buf, noremap = true, silent = true }
	vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], opts_keymap)
	vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], opts_keymap)
	vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], opts_keymap)
	vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]], opts_keymap)

	-- Auto-insert and focus tracking
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		buffer = buf,
		callback = function()
			if vim.bo.buftype == "terminal" then
				vim.cmd("startinsert")
			end
			M.last_focused_float = vim.api.nvim_get_current_win()
		end,
	})

	-- Helper function to find a suitable normal window
	local function find_normal_window()
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if w ~= win and vim.api.nvim_win_is_valid(w) then
				local b = vim.api.nvim_win_get_buf(w)
				local buftype = vim.bo[b].buftype
				-- Look for normal file buffers
				if buftype == "" then
					-- Check if this is not the split buffer
					local is_split = false
					for _, sidebar_data in pairs(M.sidebars) do
						if sidebar_data.split_win == w then
							is_split = true
							break
						end
					end
					if not is_split then
						return w
					end
				end
			end
		end
		return nil
	end

	-- Prevent buffer switching: redirect to normal window
	vim.api.nvim_create_autocmd("BufWinEnter", {
		callback = function(args)
			local current_win = vim.api.nvim_get_current_win()
			-- If a different buffer is trying to enter the terminal window
			if current_win == win and args.buf ~= buf and vim.api.nvim_buf_is_valid(buf) then
				vim.schedule(function()
					if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
						return
					end

					-- Restore terminal buffer
					pcall(vim.api.nvim_win_set_buf, win, buf)

					-- Find a normal window and switch to it
					local target_win = find_normal_window()
					if target_win and vim.api.nvim_buf_is_valid(args.buf) then
						vim.api.nvim_set_current_win(target_win)
						pcall(vim.api.nvim_win_set_buf, target_win, args.buf)
					end
				end)
			end
		end,
		desc = "Prevent buffer switching in terminal window",
	})

	return terminal
end

--- Calculate width based on config
local function calculate_width(width_config)
	local editor_width = vim.o.columns
	if width_config <= 100 then
		local percentage = width_config <= 1 and width_config or (width_config / 100)
		return math.floor(editor_width * percentage)
	end
	return width_config
end

--- Create a centered floating window
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

	local win = vim.api.nvim_open_win(buf, true, opts)
	vim.cmd("startinsert")
	return win
end

--- Internal helper to create the split window for a sidebar
--- @param width number The width of the split window
--- @param float_win number|nil The associated floating window (for QuitPre protection)
--- @return number split_win The split window handle
--- @return number split_buf The split buffer handle
local function create_reserve_split(width, float_win)
	vim.cmd("botright vsplit")
	local split_win = vim.api.nvim_get_current_win()
	local split_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(split_win, split_buf)
	vim.api.nvim_win_set_width(split_win, width)

	-- Configure split window
	vim.wo[split_win].winfixwidth = true
	vim.wo[split_win].number = false
	vim.wo[split_win].relativenumber = false
	vim.wo[split_win].statuscolumn = ""
	vim.wo[split_win].signcolumn = "no"

	-- Configure split buffer to prevent manual interaction
	vim.bo[split_buf].bufhidden = "wipe"
	vim.bo[split_buf].buflisted = false
	vim.bo[split_buf].buftype = "nofile"

	-- Protect split from manual closure - close float instead
	if float_win then
		vim.api.nvim_create_autocmd("QuitPre", {
			buffer = split_buf,
			callback = function()
				-- If user tries to close the split, close the float instead
				if vim.api.nvim_win_is_valid(float_win) then
					vim.schedule(function()
						if vim.api.nvim_win_is_valid(float_win) then
							vim.api.nvim_win_close(float_win, false)
						end
					end)
					return true -- Cancel the quit of the split
				end
			end,
			desc = "Redirect split close to float close",
		})
	end

	return split_win, split_buf
end

--- Create the Sidebar layout (Split for space + Floating for content)
--- @param buf number Terminal buffer
--- @param win_opts table Window options
--- @return number|nil The floating window handle
function M.create_sidebar_layout(buf, win_opts)
	local width_config = win_opts.min_width or win_opts.width or 34
	local padding = win_opts.padding or 0
	local configured_width = calculate_width(width_config)

	-- Calculate actual widths:
	-- - Float width: configured width minus padding on both sides
	-- - Split width: same as float width (they should be aligned)
	local float_width = configured_width - (padding * 2)
	local split_width = float_width

	-- 1. Create split (reserve space) - same width as float for alignment
	-- Note: We pass nil for float_win initially, will update protection after float is created
	local split_win, split_buf = create_reserve_split(split_width, nil)

	-- 2. Create float with padding adjustment
	local float_opts = {
		relative = "editor",
		width = float_width,
		height = 10, -- Placeholder
		row = 0,
		col = vim.o.columns - split_width, -- Aligned with split
		style = "minimal",
		border = win_opts.border or "none",
		title = win_opts.title or "",
		title_pos = "center",
		zindex = 45,
	}

	local float_win = vim.api.nvim_open_win(buf, true, float_opts)

	-- Now update the split's QuitPre autocmd with the actual float_win
	if padding > 0 then
		vim.api.nvim_create_autocmd("QuitPre", {
			buffer = split_buf,
			callback = function()
				if vim.api.nvim_win_is_valid(float_win) then
					vim.schedule(function()
						if vim.api.nvim_win_is_valid(float_win) then
							vim.api.nvim_win_close(float_win, false)
						end
					end)
					return true
				end
			end,
			desc = "Redirect split close to float close",
		})
	end

	-- 3. Link data (store padding for resize operations)
	M.sidebars[float_win] = {
		split_win = split_win,
		split_buf = split_buf,
		terminal_buf = buf,
		width_config = width_config,
		win_opts = win_opts,
		padding = padding,
	}

	-- 4. Initial geometry
	M.update_sidebar_geometry(float_win, false, true)

	-- 5. Focus & Navigation
	attach_sidebar_focus_logic(split_buf, split_win, float_win)

	-- 6. Cleanup
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(float_win),
		callback = function()
			local data = M.sidebars[float_win]
			if data and vim.api.nvim_win_is_valid(data.split_win) then
				vim.api.nvim_win_close(data.split_win, true)
			end
			if data and vim.api.nvim_buf_is_valid(data.split_buf) then
				vim.api.nvim_buf_delete(data.split_buf, { force = true })
			end
			M.sidebars[float_win] = nil
			if M.last_focused_float == float_win then
				M.last_focused_float = nil
			end
		end,
		once = true,
	})

	-- 7. Resizing setup (handles editor resize AND manual split resize)
	if not M.resized_autocmd_setup then
		local group = vim.api.nvim_create_augroup("CliIntegrationResize", { clear = true })
		vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
			group = group,
			callback = function()
				M.resize_sidebars()
				-- Cleanup autocmd if no sidebars remain
				if vim.tbl_count(M.sidebars) == 0 then
					pcall(vim.api.nvim_del_augroup_by_name, "CliIntegrationResize")
					M.resized_autocmd_setup = false
				end
			end,
			desc = "Resize CLI integration sidebars on window/editor resize",
		})
		M.resized_autocmd_setup = true
	end

	vim.cmd("startinsert")
	return float_win
end

--- Update sidebar geometry (handles maximizing/restoring and precise height)
--- @param float_win number The floating window handle
--- @param is_expanded boolean Whether to show at maximum width
--- @param should_focus boolean|nil Whether to focus the window (default: false)
function M.update_sidebar_geometry(float_win, is_expanded, should_focus)
	local data = M.sidebars[float_win]
	if not data or not vim.api.nvim_win_is_valid(float_win) then
		return
	end

	local width, height, col, border, border_offset
	local padding = data.padding or 0

	if is_expanded then
		-- Force rounded borders when maximized
		border = "rounded"
		border_offset = 2

		if vim.api.nvim_win_is_valid(data.split_win) then
			vim.api.nvim_win_close(data.split_win, true)
		end
		-- When expanded, use full width minus border offset
		width = vim.o.columns - border_offset
		col = 1
		-- Max height calculation with borders
		height = vim.o.lines - vim.o.cmdheight - border_offset - 1
	else
		-- Use configured border for normal sidebar (default: none)
		border = data.win_opts.border or "none"
		border_offset = (border == "none" or border == "") and 0 or 2

		-- Calculate widths using the same logic as create_sidebar_layout:
		-- - configured_width: the width from config
		-- - float_width: configured_width minus padding on both sides
		-- - split_width: same as float_width (aligned)
		local configured_width
		if vim.api.nvim_win_is_valid(data.split_win) then
			-- If split exists, use its current width as the float width
			width = vim.api.nvim_win_get_width(data.split_win)
			col = vim.o.columns - width
		else
			-- Recalculate from config
			configured_width = calculate_width(data.width_config)
			width = configured_width - (padding * 2)
			col = vim.o.columns - width

			-- Recreate split with same width as float
			local split_win, split_buf = create_reserve_split(width, float_win)
			data.split_win = split_win
			data.split_buf = split_buf
			attach_sidebar_focus_logic(split_buf, split_win, float_win)
		end

		local split_row, _ = unpack(vim.api.nvim_win_get_position(data.split_win))
		local split_height = vim.api.nvim_win_get_height(data.split_win)
		-- Height = space from top (split_row) + split content area - border_offset
		-- This ensures the float covers the entire split area vertically
		height = split_row + split_height - border_offset
	end

	vim.api.nvim_win_set_config(float_win, {
		relative = "editor",
		border = border,
		width = width,
		height = height,
		row = 0,
		col = col,
	})

	-- Ensure focus and insert mode ONLY if it was already focused or explicitly requested
	local current_win = vim.api.nvim_get_current_win()
	if (should_focus or current_win == float_win) and vim.api.nvim_win_is_valid(float_win) then
		vim.api.nvim_set_current_win(float_win)
		vim.cmd("startinsert")
	end
end

--- Resize all sidebars
function M.resize_sidebars()
	for float_win, data in pairs(M.sidebars) do
		if vim.api.nvim_win_is_valid(float_win) then
			local is_expanded = not vim.api.nvim_win_is_valid(data.split_win)
			M.update_sidebar_geometry(float_win, is_expanded, false)
		else
			M.sidebars[float_win] = nil
		end
	end
end

--- Toggle terminal window visibility
--- @param terminal TerminalWindow Terminal object
--- @return nil
function M.toggle_terminal(terminal)
	if not terminal or not terminal.buf or not vim.api.nvim_buf_is_valid(terminal.buf) then
		return
	end

	if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
		vim.api.nvim_win_close(terminal.win, false)
		terminal.win = nil
	else
		local win_opts = terminal.opts.win or {}
		local win = (win_opts.position == "float") and M.create_float_window(terminal.buf, win_opts)
			or M.create_sidebar_layout(terminal.buf, win_opts)
		if win then
			terminal.win = win
		end
	end
end

--- Check if a terminal window is visible
--- @param terminal TerminalWindow Terminal object
--- @return boolean
function M.is_terminal_visible(terminal)
	return terminal ~= nil and terminal.win ~= nil and vim.api.nvim_win_is_valid(terminal.win)
end

return M
