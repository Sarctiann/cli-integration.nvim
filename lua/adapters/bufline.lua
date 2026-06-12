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

--- Inject a single bufferline offset for the sidebar vsplit, so bufferline
--- does not draw over the integration window.  Best-effort: no-op if
--- bufferline is absent.
--- @param term_buf number
--- @param title string
function M.inject_offset(term_buf, title)
	local ok, bc = pcall(require, "bufferline.config")
	if not ok then
		return
	end

	local cfg = bc.get()
	if not cfg or not cfg.options then
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

return M
