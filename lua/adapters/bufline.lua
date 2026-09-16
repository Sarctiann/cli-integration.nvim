local M = {}

--- Remove ALL bufferline offset entries belonging to this plugin.
--- Bufferline with `filetype` offsets independently calculates the width
--- for EACH entry by summing all windows with that filetype.  Having
--- multiple entries causes double-counting and pushes bufferline off-screen.
--- @param cfg table bufferline config
local function remove_all_plugin_offsets(cfg)
	if not cfg.options or not cfg.options.offsets then
		return
	end
	for i = #cfg.options.offsets, 1, -1 do
		if cfg.options.offsets[i]._cli_integration_buf then
			table.remove(cfg.options.offsets, i)
		end
	end
end

--- @return table|nil
local function get_config()
	local ok, bc = pcall(require, "bufferline.config")
	if not ok then
		return nil
	end
	local cfg = bc.get()
	if not cfg or not cfg.options then
		return nil
	end
	return cfg
end

--- Whether we've overridden bufferline's own `always_show_bufferline`, and
--- what to restore it to. nil means "not currently overridden".
M._prev_always_show = nil

--- Cooperate with bufferline's own tabline-visibility logic instead of
--- fighting it. bufferline decides whether to show the tabline on every
--- redraw (`toggle_bufferline()`, bound to its own high-frequency redraw
--- path) purely from its `always_show_bufferline` option — it has no idea
--- our integration window wants the tabline kept visible. Forcing
--- `showtabline` back to 2 from the outside every time bufferline hides it
--- creates a fight: each of bufferline's redraws (many per second while a
--- CLI tool is streaming output) flips showtabline 2->0, and reverting it
--- retriggers a global chrome resize for every window in the tabpage —
--- an autocmd storm that is a real source of window-size drift/corruption.
--- Flipping bufferline's OWN flag instead means it simply stops wanting to
--- hide the tabline, so there's nothing left to fight.
--- @param enabled boolean
function M.set_always_show(enabled)
	local cfg = get_config()
	if not cfg then
		if enabled then
			-- No bufferline installed/active: just force it once directly.
			vim.o.showtabline = 2
		end
		return
	end

	if enabled then
		if M._prev_always_show == nil then
			M._prev_always_show = cfg.options.always_show_bufferline or false
		end
		cfg.options.always_show_bufferline = true
		if vim.o.showtabline ~= 2 then
			vim.o.showtabline = 2
		end
	elseif M._prev_always_show ~= nil then
		cfg.options.always_show_bufferline = M._prev_always_show
		M._prev_always_show = nil
	end
end

--- Inject a single bufferline offset for the sidebar vsplit, so bufferline
--- does not draw over the integration window.  Best-effort: no-op if
--- bufferline is absent.
--- @param term_buf number
--- @param title string
function M.inject_offset(term_buf, title)
	local cfg = get_config()
	if not cfg then
		return
	end

	cfg.options.offsets = cfg.options.offsets or {}

	remove_all_plugin_offsets(cfg)

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

--- Remove all plugin-owned offset entries and redraw the tabline.
--- Safe to call even when no plugin offsets exist.
function M.restore()
	local cfg = get_config()
	if not cfg then
		return
	end
	remove_all_plugin_offsets(cfg)
	M.set_always_show(false)
	vim.schedule(function()
		vim.cmd("redrawtabline")
	end)
end

return M
