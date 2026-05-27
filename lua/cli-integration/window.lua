--- Window and terminal management using native Neovim API
--- @class TerminalWindow
--- @field buf number Buffer number
--- @field win number|nil Window number (floating window)
--- @field job_id number Job ID
--- @field cmd string Command being run
--- @field opts table Terminal options
--- @field on_close function|nil Callback when terminal closes
--- @field toggle function|nil
local M = {}
local debug = require("cli-integration.debug")

--- Store active sidebar configurations
--- Keyed by term_buf (stable across toggles)
--- Format: [term_buf] = {
---   term_buf              = number,        -- stable key
---   mode                  = string,        -- "sidebar" | "float" | "fullscreen"
---   origin                = string,        -- "sidebar" | "float" (never changes)
---   sidebar_win           = number|nil,    -- vsplit handle; valid but hidden when mode == "fullscreen"
---   float_win             = number|nil,    -- float handle; active when mode == "fullscreen" or origin == "float"
---   float_original        = table|nil,     -- saved float config for float-origin restore
---   fullscreen_autocmd_id = number|nil,    -- autocmd id of WinClosed guard on fullscreen float
---   width_config          = number,
---   win_opts              = table,
---   padding               = number,
---   list_buffer           = boolean,
--- }
M.sidebars = {}

--- Check if a window is an integration window for a given terminal buffer
--- @param win number Window handle
--- @param term_buf number Terminal buffer
--- @return boolean
local function is_integration_window(win, term_buf)
	local data = M.sidebars[term_buf]
	return data ~= nil and (data.sidebar_win == win or data.float_win == win)
end

--- @param w number Window handle
--- @return boolean
local function is_any_integration_win(w)
	for _, d in pairs(M.sidebars) do
		if d.sidebar_win == w or d.float_win == w then
			return true
		end
	end
	return false
end

local function is_valid_win(win)
	return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end

--- Apply sidebar window options to a vsplit window.
--- Called both on initial creation and after restoring a hidden vsplit to the layout.
--- @param win number Window handle
--- @param padding number Horizontal padding (foldcolumn)
local function apply_sidebar_win_opts(win, padding)
	vim.wo[win].winfixwidth = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].cursorline = false
	vim.wo[win].spell = false
	vim.wo[win].winhighlight = "Normal:NormalSB,NormalNC:NormalSB,EndOfBuffer:NormalSB"
	if padding > 0 then
		vim.wo[win].foldcolumn = tostring(padding)
	end
end

--- Remove the bufferline offset entry for a given term_buf.
--- @param term_buf number
local function remove_bufferline_offset(term_buf)
	local ok, bc = pcall(require, "bufferline.config")
	if not ok then
		return
	end

	local cfg = bc.get()
	if not cfg or not cfg.options or not cfg.options.offsets then
		return
	end

	for i, offset in ipairs(cfg.options.offsets) do
		if offset._cli_integration_buf == term_buf then
			table.remove(cfg.options.offsets, i)
			vim.schedule(function()
				vim.cmd("redrawtabline")
			end)
			return
		end
	end
end

--- Inject a bufferline offset for the sidebar vsplit, so bufferline does not
--- draw over the integration window. Best-effort: no-op if bufferline is absent.
--- @param term_buf number
--- @param title string
local function inject_bufferline_offset(term_buf, title)
	local ok, bc = pcall(require, "bufferline.config")
	if not ok then
		return
	end

	local cfg = bc.get()
	if not cfg or not cfg.options then
		return
	end

	cfg.options.offsets = cfg.options.offsets or {}

	-- Remove any stale entry for the same buffer before adding a new one
	remove_bufferline_offset(term_buf)

	table.insert(cfg.options.offsets, {
		filetype = "cli-integration",
		text = title,
		highlight = "NormalSB",
		separator = true,
		_cli_integration_buf = term_buf,
	})
	vim.schedule(function()
		vim.cmd("redrawtabline")
	end)
end

--- Resize the pty of a terminal job to match current window content dimensions.
--- Sends SIGWINCH so TUI apps update their internal size and mouse coordinates.
--- @param term_buf number Terminal buffer handle
--- @param win number Window handle (must be valid)
--- @param border string|table Border style
--- @param padding number Horizontal padding
local function resize_pty(term_buf, win, border, padding)
	local job_id = vim.bo[term_buf].channel
	if not job_id or job_id <= 0 then
		return
	end
	local w = vim.api.nvim_win_get_width(win)
	local h = vim.api.nvim_win_get_height(win)
	local border_offset
	if type(border) == "table" then
		border_offset = (#border > 0) and 2 or 0
	else
		border_offset = (border == nil or border == "none" or border == "") and 0 or 2
	end
	local content_width = math.max(1, w - border_offset - (padding * 2))
	local content_height = math.max(1, h - border_offset)
	pcall(vim.fn.jobresize, job_id, content_width, content_height)
end

--- Build terminal job environment starting from inherited process env,
--- then applying explicit overrides and removals.
--- @param opts table
--- @param cols number
--- @param lines number
--- @return table<string, string>
local function build_job_env(opts, cols, lines)
	local env = vim.fn.environ()

	-- Strip tmux identity vars: the job's pty is owned by Neovim, not tmux.
	env.TMUX = nil
	env.TMUX_PANE = nil
	env.TERM_PROGRAM = nil
	env.TERM_PROGRAM_VERSION = nil

	-- Strip Ghostty identity vars: if detected, TUI libs enable Ghostty-specific
	-- escape sequences that Neovim's terminal emulator doesn't handle (garbage chars).
	env.GHOSTTY_RESOURCES_DIR = nil
	env.GHOSTTY_SHELL_FEATURES = nil
	env.GHOSTTY_BIN_DIR = nil
	env.TERMINFO = nil

	-- Normalize TERM/COLORTERM: host terminals like Ghostty set TERM=xterm-ghostty
	-- which causes TUI apps to enable capabilities Neovim's terminal doesn't handle.
	env.COLUMNS = tostring(cols)
	env.LINES = tostring(lines)

	-- Override TERM/COLORTERM to safe defaults unless user sets them explicitly.
	-- Do NOT remove without testing Ghostty + tmux + Neovim :terminal with opencode/lazygit.
	if not (type(opts.env) == "table" and opts.env.TERM ~= nil) then
		env.TERM = "xterm-256color"
	end
	if not (type(opts.env) == "table" and opts.env.COLORTERM ~= nil) then
		env.COLORTERM = "truecolor"
	end

	if type(opts.env) == "table" then
		env = vim.tbl_extend("force", env, opts.env)
	end

	if type(opts.unset_env) == "table" then
		for _, key in ipairs(opts.unset_env) do
			env[key] = nil
		end
	end

	return env
end

M.resized_autocmd_setup = false

--- Track last known editor width to distinguish editor resize from manual split resize
M._last_editor_width = vim.o.columns

--- Calculate width based on config (percentage or absolute)
--- @param width_config number Width configuration (1-100 for percentage, >100 for absolute)
--- @return number Calculated width in columns
local function calculate_width(width_config)
	local editor_width = vim.o.columns
	if width_config <= 100 then
		local percentage = width_config <= 1 and width_config or (width_config / 100)
		return math.floor(editor_width * percentage)
	end
	return width_config
end

--- Calculate the usable content dimensions of a terminal window,
--- subtracting border cells and padding.
--- @param win number Window handle (must be valid and sized)
--- @param border string|table Border style ("none"|"single"|"double"|"rounded"|"solid"|"shadow") or 8-element array
--- @param padding number Horizontal padding in columns (foldcolumn)
--- @return number cols  Usable columns (COLUMNS env var)
--- @return number lines Usable lines  (LINES env var)
local function calculate_content_dimensions(win, border, padding)
	local w = vim.api.nvim_win_get_width(win)
	local h = vim.api.nvim_win_get_height(win)
	local border_offset
	if type(border) == "table" then
		border_offset = (#border > 0) and 2 or 0
	else
		border_offset = (border == nil or border == "none" or border == "") and 0 or 2
	end
	local cols = math.max(1, w - border_offset - (padding * 2))
	local lines = math.max(1, h - border_offset)
	return cols, lines
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

	local buf = vim.api.nvim_create_buf(false, true)
	if not buf or buf == 0 then
		return nil
	end

	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].buflisted = false

	-- Set buffer variable for integration identification BEFORE termopen/jobstart
	-- so TermOpen autocmds can identify which integration this terminal belongs to.
	if win_opts.integration_name and win_opts.integration_name ~= "" then
		vim.api.nvim_buf_set_var(buf, "cli_integration_name", win_opts.integration_name)
	end

	local is_float = win_opts.position == "float"
	local win

	if is_float then
		win = M.create_float_window(buf, win_opts)
	else
		win = M.create_sidebar_layout(buf, win_opts)
	end

	if not win then
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].spell = false
	vim.wo[win].cursorline = false

	---@type TerminalWindow
	local terminal = {
		buf = buf,
		win = win,
		job_id = 0,
		cmd = cmd,
		opts = opts,
		on_close = win_opts.on_close,
	}

	terminal.toggle = function()
		M.toggle_terminal(terminal)
	end
	local integration_name = win_opts.integration_name or ""

	-- Read final content dimensions AFTER geometry is established.
	-- create_sidebar_layout sets the vsplit width before returning, so
	-- win dimensions are correct here.
	local padding = win_opts.padding or 0
	local border = win_opts.border or (is_float and "rounded" or "none")
	local cols, lines = calculate_content_dimensions(win, border, padding)

	local job_id
	vim.api.nvim_buf_call(buf, function()
		local original_cwd = vim.fn.getcwd()
		if cwd and cwd ~= "" then
			vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
		end

		local env = build_job_env(opts, cols, lines)
		debug.log("create_terminal", function()
			return {
				cmd = cmd,
				buf = buf,
				integration_name = integration_name,
				width = cols,
				height = lines,
			}
		end)

		local use_jobstart = vim.fn.has("nvim-0.11") == 1
		local job_opts = {
			cwd = cwd,
			env = env,
			term = true,
			on_exit = function(_, exit_code, _)
				if auto_close and exit_code == 0 then
					vim.schedule(function()
						local title = (win_opts.title ~= "" and win_opts.title) or "cli"
						local msg = "... bye bye" .. title .. " "
						local notif_buf = vim.api.nvim_create_buf(false, true)
						vim.api.nvim_buf_set_lines(notif_buf, 0, -1, false, { msg })
						local width = #msg
						local notif_win = vim.api.nvim_open_win(notif_buf, false, {
							relative = "editor",
							width = width,
							height = 1,
							row = vim.o.lines - 4,
							col = vim.o.columns - width - 2,
							style = "minimal",
							border = "rounded",
							focusable = false,
						})
						vim.defer_fn(function()
							pcall(vim.api.nvim_win_close, notif_win, true)
							pcall(vim.api.nvim_buf_delete, notif_buf, { force = true })
						end, 1000)
					end)
					vim.defer_fn(function()
						if vim.api.nvim_buf_is_valid(buf) then
							vim.api.nvim_buf_delete(buf, { force = true })
						end
					end, 1000)
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

	if padding > 0 then
		vim.wo[win].foldcolumn = tostring(padding)
	end

	if not job_id or job_id <= 0 then
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	terminal.job_id = job_id

	-- List buffer in bufferline if configured (must be after termopen so buftype=terminal is set)
	if opts.win and opts.win.list_buffer then
		vim.bo[buf].buflisted = true
	end

	-- Set/re-apply buffer name after termopen/jobstart (Neovim overwrites with term://...)
	if win_opts.buffer_name and win_opts.buffer_name ~= "" then
		pcall(vim.api.nvim_buf_set_name, buf, win_opts.buffer_name)
	end

	local keymap_opts = { buffer = buf, noremap = true, silent = true }
	vim.keymap.set("t", "<C-h>", [[<C-\><C-n><Cmd>wincmd h<CR>]], keymap_opts)
	vim.keymap.set("t", "<C-j>", [[<C-\><C-n><Cmd>wincmd j<CR>]], keymap_opts)
	vim.keymap.set("t", "<C-k>", [[<C-\><C-n><Cmd>wincmd k<CR>]], keymap_opts)
	vim.keymap.set("t", "<C-l>", [[<C-\><C-n><Cmd>wincmd l<CR>]], keymap_opts)

	-- Only enter insert on click inside this terminal window; otherwise let
	-- default mouse behavior handle window focus change.
	if opts.win and opts.win.start_insert_on_click then
		local click_opts = { buffer = buf, noremap = true, silent = true, expr = true }
		local click_fn = function()
			local mouse_pos = vim.fn.getmousepos()
			local current_win = vim.api.nvim_get_current_win()
			if mouse_pos.winid == current_win and is_integration_window(current_win, buf) then
				return "i"
			else
				return "<LeftMouse>"
			end
		end
		vim.keymap.set("n", "<LeftMouse>", click_fn, click_opts)
		vim.keymap.set("n", "<2-LeftMouse>", click_fn, click_opts)
	end

	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		buffer = buf,
		callback = function()
			if vim.bo[buf].buftype == "terminal" then
				vim.cmd("startinsert")
			end
		end,
		desc = "Auto-enter insert mode in terminal",
	})

	-- Prevent buffer switching: terminal window must only show its terminal buffer.
	-- Also handles list_buffer edge case: allow load in regular window when integration
	-- window is hidden in bufferline.
	vim.api.nvim_create_autocmd("BufWinEnter", {
		callback = function(args)
			if args.buf == buf then
				return
			end

			local current_win = vim.api.nvim_get_current_win()
			local data = M.sidebars[buf]
			local is_our_win = data ~= nil and (current_win == data.sidebar_win or current_win == data.float_win)

			-- Case 1: current_win is integration window and different buffer loaded
			if is_our_win then
				vim.schedule(function()
					if not vim.api.nvim_win_is_valid(current_win) or not vim.api.nvim_buf_is_valid(buf) then
						return
					end

					pcall(vim.api.nvim_win_set_buf, current_win, buf)

					local target_win = nil
					local fallback_win = nil
					for _, w in ipairs(vim.api.nvim_list_wins()) do
						if w ~= current_win and vim.api.nvim_win_is_valid(w) then
							local b = vim.api.nvim_win_get_buf(w)
							local bt = vim.bo[b].buftype
							if bt == "" then
								target_win = w
								break
							elseif not fallback_win and bt ~= "terminal" and bt ~= "nofile" then
								fallback_win = w
							end
						end
					end

					local dest = target_win or fallback_win
					if not dest then
						vim.cmd("vsplit")
						dest = vim.api.nvim_get_current_win()
					end

					if dest and vim.api.nvim_buf_is_valid(args.buf) then
						vim.api.nvim_set_current_win(dest)
						pcall(vim.api.nvim_win_set_buf, dest, args.buf)
					end
				end)
				return
			end

			-- Case 2: current_win is regular window and args.buf is terminal buffer
			if args.buf == buf then
				local integration_win = nil
				if data then
					if data.sidebar_win and vim.api.nvim_win_is_valid(data.sidebar_win) then
						integration_win = data.sidebar_win
					elseif data.float_win and vim.api.nvim_win_is_valid(data.float_win) then
						integration_win = data.float_win
					end
				end
				if integration_win then
					vim.api.nvim_set_current_win(integration_win)
					vim.schedule(function()
						if vim.api.nvim_win_is_valid(integration_win) then
							vim.cmd("startinsert")
						end
					end)
				end
			end
		end,
		desc = "Lock terminal window to terminal buffer only; handle list_buffer window separation",
	})

	-- WinEnter guard: restore terminal buffer if a wrong buffer ends up here.
	vim.api.nvim_create_autocmd("WinEnter", {
		callback = function()
			local current_win = vim.api.nvim_get_current_win()
			if not is_integration_window(current_win, buf) then
				return
			end

			if
				vim.api.nvim_get_current_buf() ~= buf
				and vim.api.nvim_buf_is_valid(buf)
				and vim.api.nvim_win_is_valid(current_win)
			then
				pcall(vim.api.nvim_win_set_buf, current_win, buf)
			end
		end,
		desc = "Secondary guard: restore terminal buffer on WinEnter in integration window",
	})

	return terminal
end

--- Create a centered floating window
--- @param buf number Terminal buffer
--- @param win_opts table Window options
--- @return number|nil The floating window handle
function M.create_float_window(buf, win_opts)
	local width = win_opts.width or math.floor(vim.o.columns * 0.8)
	local height = win_opts.height or math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local float_opts = {
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

	local win = vim.api.nvim_open_win(buf, true, float_opts)
	debug.log("create_float_window", function()
		return { buf = buf, win = win, width = width, height = height }
	end)

	M.sidebars[buf] = {
		term_buf = buf,
		mode = "float",
		origin = "float",
		sidebar_win = nil,
		float_win = win,
		float_original = { width = width, height = height, row = row, col = col },
		fullscreen_autocmd_id = nil,
		width_config = width,
		win_opts = win_opts,
		padding = 0,
		list_buffer = win_opts.list_buffer or false,
	}

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		callback = function()
			M.sidebars[buf] = nil
		end,
		once = true,
		desc = "Cleanup float-origin entry on close",
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = buf,
		callback = function()
			vim.schedule(function()
				vim.cmd("stopinsert")
			end)
		end,
		desc = "Exit insert mode when leaving terminal window",
	})

	vim.cmd("startinsert")
	return win
end

--- Find a safe anchor window in the normal layout for creating splits
--- @return number|nil
function M.find_layout_anchor_window()
	-- First pass: prefer a normal file buffer window (buftype == "")
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and not is_any_integration_win(win) then
			local cfg = vim.api.nvim_win_get_config(win)
			if cfg.relative == "" then
				local buf = vim.api.nvim_win_get_buf(win)
				local bt = vim.bo[buf].buftype
				if bt == "" then
					return win
				end
			end
		end
	end

	-- Second pass: any non-floating window
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and not is_any_integration_win(win) then
			local cfg = vim.api.nvim_win_get_config(win)
			if cfg.relative == "" then
				return win
			end
		end
	end

	return nil
end

--- Create the Sidebar layout (vsplit terminal on right side)
--- @param buf number Terminal buffer
--- @param win_opts table Window options
--- @return number|nil The vsplit window handle
function M.create_sidebar_layout(buf, win_opts)
	local width_config = win_opts.min_width or win_opts.width or 34
	local padding = win_opts.padding or 0
	local configured_width = calculate_width(width_config)

	local vsplit_width = configured_width - (padding * 2)

	local anchor_win = M.find_layout_anchor_window()
	if anchor_win and vim.api.nvim_win_is_valid(anchor_win) then
		pcall(vim.api.nvim_set_current_win, anchor_win)
	end
	vim.cmd("botright vsplit")
	local sidebar_win = vim.api.nvim_get_current_win()

	vim.api.nvim_win_set_buf(sidebar_win, buf)

	-- Set filetype for bufferline offset detection
	vim.bo[buf].filetype = "cli-integration"

	-- Set width BEFORE returning so calculate_content_dimensions reads the final width.
	vim.api.nvim_win_set_width(sidebar_win, vsplit_width)

	apply_sidebar_win_opts(sidebar_win, padding)

	-- Inject bufferline offset so tabline doesn't overlap the sidebar
	inject_bufferline_offset(buf, win_opts.title or "")

	-- Merge with existing entry if one exists (e.g. fullscreen restore creates a new
	-- vsplit but we want to preserve the existing entry's fields).
	local existing = M.sidebars[buf]
	if existing then
		existing.sidebar_win = sidebar_win
		existing.mode = "sidebar"
		existing.float_win = nil
		existing.float_original = nil
		existing.fullscreen_autocmd_id = nil
	else
		M.sidebars[buf] = {
			term_buf = buf,
			mode = "sidebar",
			origin = "sidebar",
			sidebar_win = sidebar_win,
			float_win = nil,
			float_original = nil,
			fullscreen_autocmd_id = nil,
			width_config = width_config,
			win_opts = win_opts,
			padding = padding,
			list_buffer = win_opts.list_buffer or false,
		}
	end

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(sidebar_win),
		callback = function()
			local data = M.sidebars[buf]
			if data then
				data.sidebar_win = nil
			end
			remove_bufferline_offset(buf)
		end,
		once = true,
		desc = "Clear sidebar reference on vsplit close",
	})

	M._last_editor_width = vim.o.columns
	if not M.resized_autocmd_setup then
		local group = vim.api.nvim_create_augroup("CliIntegrationResize", { clear = true })
		vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
			group = group,
			callback = function()
				M.resize_sidebars()
				if vim.tbl_count(M.sidebars) == 0 then
					pcall(vim.api.nvim_del_augroup_by_name, "CliIntegrationResize")
					M.resized_autocmd_setup = false
				end
			end,
			desc = "Resize sidebar on editor resize",
		})
		M.resized_autocmd_setup = true
	end

	vim.cmd("startinsert")
	debug.log("create_sidebar_layout", function()
		return { buf = buf, sidebar_win = sidebar_win, width = vsplit_width }
	end)
	return sidebar_win
end

--- Update sidebar geometry (handles fullscreen toggle for sidebar-origin integrations)
--- @param term_buf number The terminal buffer (key into M.sidebars)
--- @param is_fullscreen boolean Whether to show in fullscreen mode
--- @param should_focus boolean|nil Whether to focus the window (default: false)
function M.update_sidebar_geometry(term_buf, is_fullscreen, should_focus)
	local data = M.sidebars[term_buf]
	if not data or data.origin ~= "sidebar" then
		return
	end
	local from_mode = data.mode

	if is_fullscreen then
		-- Fullscreen mode: hide vsplit, open fullscreen float.
		debug.log("update_sidebar_geometry", function()
			return {
				term_buf = term_buf,
				from_mode = from_mode,
				to_mode = "fullscreen",
				sidebar_win = data.sidebar_win,
				float_win = data.float_win,
			}
		end)
		-- Collapse vsplit to width 1 instead of hiding/closing.
		-- nvim_win_hide does not work for splits; closing destroys the window.
		-- Keeping it alive avoids recreation artifacts (dashes) on restore.
		if data.sidebar_win and is_valid_win(data.sidebar_win) then
			pcall(vim.api.nvim_win_set_width, data.sidebar_win, 1)
		end
		remove_bufferline_offset(term_buf)

		local float_opts = {
			relative = "editor",
			width = vim.o.columns,
			height = vim.o.lines - vim.o.cmdheight - 1,
			row = 0,
			col = 0,
			style = "minimal",
			border = "single",
			title = data.win_opts.title or "",
			title_pos = "center",
		}

		local new_win = vim.api.nvim_open_win(data.term_buf, true, float_opts)

		if new_win then
			vim.wo[new_win].number = false
			vim.wo[new_win].relativenumber = false
			vim.wo[new_win].signcolumn = "no"
			vim.wo[new_win].spell = false
			vim.wo[new_win].cursorline = false

			data.float_win = new_win
			data.mode = "fullscreen"

			local autocmd_id = vim.api.nvim_create_autocmd("WinClosed", {
				pattern = tostring(new_win),
				callback = function()
					remove_bufferline_offset(term_buf)
					M.sidebars[term_buf] = nil
				end,
				once = true,
				desc = "Cleanup fullscreen float on close",
			})
			data.fullscreen_autocmd_id = autocmd_id

			resize_pty(data.term_buf, new_win, "single", data.padding or 0)

			if should_focus then
				vim.api.nvim_set_current_win(new_win)
				vim.schedule(function()
					if is_valid_win(new_win) then
						vim.cmd("startinsert")
					end
				end)
			end
		end
	else
		-- Sidebar mode: close float, restore or recreate vsplit
		debug.log("update_sidebar_geometry", function()
			return {
				term_buf = term_buf,
				from_mode = from_mode,
				to_mode = "sidebar",
				sidebar_win = data.sidebar_win,
				float_win = data.float_win,
			}
		end)
		local float_win = data.float_win

		if data.fullscreen_autocmd_id then
			pcall(vim.api.nvim_del_autocmd, data.fullscreen_autocmd_id)
			data.fullscreen_autocmd_id = nil
		end

		if float_win and is_valid_win(float_win) then
			pcall(vim.api.nvim_win_close, float_win, true)
			data.float_win = nil
		end

		-- Expand the collapsed vsplit back to its configured width.
		local sidebar_win = data.sidebar_win
		if sidebar_win and is_valid_win(sidebar_win) then
			local configured_width = calculate_width(data.width_config)
			local target_width = configured_width - (data.padding or 0) * 2
			pcall(vim.api.nvim_win_set_width, sidebar_win, target_width)
			-- vsplit restored
		else
			-- Fallback: recreate if the window was closed externally
			local fallback_win = M.create_sidebar_layout(data.term_buf, data.win_opts)
			if fallback_win then
				data.sidebar_win = fallback_win
			end
		end

		sidebar_win = data.sidebar_win
		if sidebar_win and is_valid_win(sidebar_win) then
			inject_bufferline_offset(data.term_buf, data.win_opts.title or "")
			resize_pty(data.term_buf, sidebar_win, "none", data.padding or 0)
			if should_focus then
				vim.api.nvim_set_current_win(sidebar_win)
				vim.schedule(function()
					if is_valid_win(sidebar_win) then
						vim.cmd("startinsert")
					end
				end)
			end
		end
	end
end

--- Update float geometry (handles fullscreen toggle for float-origin integrations)
--- @param term_buf number The terminal buffer (key into M.sidebars)
--- @param is_fullscreen boolean Whether to show in fullscreen mode
--- @param should_focus boolean|nil Whether to focus the window (default: false)
function M.update_float_geometry(term_buf, is_fullscreen, should_focus)
	local data = M.sidebars[term_buf]
	if not data or data.origin ~= "float" then
		return
	end

	local float_win = data.float_win
	if not float_win or not is_valid_win(float_win) then
		return
	end
	local original_mode = data.mode

	if is_fullscreen then
		local cfg = vim.api.nvim_win_get_config(float_win)
		data.float_original = {
			width = cfg.width,
			height = cfg.height,
			row = cfg.row,
			col = cfg.col,
			border = cfg.border,
		}

		debug.log("update_float_geometry", function()
			return {
				term_buf = term_buf,
				from_mode = original_mode,
				to_mode = "fullscreen",
				float_win = float_win,
			}
		end)
		pcall(vim.api.nvim_win_set_config, float_win, {
			relative = "editor",
			width = vim.o.columns,
			height = vim.o.lines - vim.o.cmdheight - 1,
			row = 0,
			col = 0,
			style = "minimal",
			border = "single",
		})

		data.mode = "fullscreen"
		resize_pty(data.term_buf, float_win, "single", data.padding or 0)
	else
		debug.log("update_float_geometry", function()
			return {
				term_buf = term_buf,
				from_mode = original_mode,
				to_mode = "float",
				float_win = float_win,
			}
		end)
		local orig = data.float_original
		if orig then
			local border = data.win_opts.border or "rounded"
			pcall(vim.api.nvim_win_set_config, float_win, {
				relative = "editor",
				width = orig.width,
				height = orig.height,
				row = orig.row,
				col = orig.col,
				style = "minimal",
				border = border,
			})
			data.float_original = nil
		end

		data.mode = "float"
		local border = data.win_opts.border or "rounded"
		resize_pty(data.term_buf, float_win, border, data.padding or 0)
	end

	if should_focus then
		vim.api.nvim_set_current_win(float_win)
		vim.schedule(function()
			if is_valid_win(float_win) then
				vim.cmd("startinsert")
			end
		end)
	end
end

--- Enable or disable window-navigation keymaps for a terminal buffer.
--- @param term_buf number Terminal buffer handle
--- @param enabled boolean
function M.set_nav_keymaps_enabled(term_buf, enabled)
	if not vim.api.nvim_buf_is_valid(term_buf) then
		return
	end
	local modes = { "t", "n" }
	local opts = { buffer = term_buf, noremap = true, silent = true }

	if enabled then
		for _, mode in ipairs(modes) do
			vim.keymap.set(mode, "<C-h>", [[<C-\><C-n><Cmd>wincmd h<CR>]], opts)
			vim.keymap.set(mode, "<C-j>", [[<C-\><C-n><Cmd>wincmd j<CR>]], opts)
			vim.keymap.set(mode, "<C-k>", [[<C-\><C-n><Cmd>wincmd k<CR>]], opts)
			vim.keymap.set(mode, "<C-l>", [[<C-\><C-n><Cmd>wincmd l<CR>]], opts)
		end
	else
		for _, mode in ipairs(modes) do
			vim.keymap.set(mode, "<C-h>", "<Nop>", opts)
			vim.keymap.set(mode, "<C-j>", "<Nop>", opts)
			vim.keymap.set(mode, "<C-k>", "<Nop>", opts)
			vim.keymap.set(mode, "<C-l>", "<Nop>", opts)
		end
	end
end

--- Resize all sidebar/float windows (handles editor resize and fullscreen)
function M.resize_sidebars()
	local editor_resized = vim.o.columns ~= M._last_editor_width
	if editor_resized then
		M._last_editor_width = vim.o.columns
	end
	debug.log("resize_sidebars", function()
		return { editor_resized = editor_resized, editor_width = vim.o.columns }
	end)

	for _, data in pairs(M.sidebars) do
		if data.mode == "fullscreen" and data.float_win and is_valid_win(data.float_win) then
			pcall(vim.api.nvim_win_set_config, data.float_win, {
				relative = "editor",
				width = vim.o.columns,
				height = vim.o.lines - vim.o.cmdheight - 1,
				row = 0,
				col = 0,
				style = "minimal",
				border = "single",
			})
			resize_pty(data.term_buf, data.float_win, "single", data.padding or 0)
		elseif data.mode == "sidebar" and editor_resized and data.sidebar_win and is_valid_win(data.sidebar_win) then
			local padding = data.padding or 0
			local configured_width = calculate_width(data.width_config)
			local target_width = configured_width - (padding * 2)
			pcall(vim.api.nvim_win_set_width, data.sidebar_win, target_width)
			resize_pty(data.term_buf, data.sidebar_win, "none", data.padding or 0)
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

	local data = M.sidebars[terminal.buf]

	if data then
		local win = data.sidebar_win or data.float_win
		if win and is_valid_win(win) then
			vim.api.nvim_win_close(win, false)
			terminal.win = nil
			-- Remove bufferline offset when sidebar is hidden
			remove_bufferline_offset(terminal.buf)
		else
			local win_opts = terminal.opts.win or {}
			local new_win

			if win_opts.position == "float" then
				new_win = M.create_float_window(terminal.buf, win_opts)
			else
				new_win = M.create_sidebar_layout(terminal.buf, win_opts)
			end

			if new_win then
				terminal.win = new_win
			end
		end
	else
		local current_win = nil
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(w) == terminal.buf then
				current_win = w
				break
			end
		end

		if current_win and vim.api.nvim_win_is_valid(current_win) then
			vim.api.nvim_win_close(current_win, false)
			terminal.win = nil
		else
			local win_opts = terminal.opts.win or {}
			local new_win

			if win_opts.position == "float" then
				new_win = M.create_float_window(terminal.buf, win_opts)
			else
				new_win = M.create_sidebar_layout(terminal.buf, win_opts)
			end

			if new_win then
				terminal.win = new_win
			end
		end
	end
end

--- Check if a terminal window is visible
--- @param terminal TerminalWindow Terminal object
--- @return boolean
function M.is_terminal_visible(terminal)
	if not terminal or not terminal.buf or not vim.api.nvim_buf_is_valid(terminal.buf) then
		return false
	end
	local data = M.sidebars[terminal.buf]
	if not data then
		return false
	end
	return (data.sidebar_win and is_valid_win(data.sidebar_win)) or (data.float_win and is_valid_win(data.float_win))
end

return M
