local M = {}
local api = vim.api

function M.toggle_menu()
  local UI = require('trident.ui')
  if UI.winid ~= -1 and api.nvim_win_is_valid(UI.winid) then
    UI.menu_close()
    return
  end
  UI.menu_buffer_create()
  UI.menu_create_window()
  require('trident.util').trigger_event('TridentWindowOpen', { bufnr = UI.bufnr, winid = UI.winid })
end

function M.add_file()
  local MRK = require('trident.mark')
  if not MRK.mark_filter_file() then
    return
  end
  local bufname = MRK.mark_get_bufname()
  local idx = MRK.mark_get_index_of(bufname)
  local config = require('trident.config')
  if MRK.mark_valid_index(idx) then
    MRK.mark_update_cursor(idx)
    if config.notify.update then
      require('trident.util').info(("'%s' updated"):format(vim.fn.fnamemodify(bufname, ':~')))
    end
  else
    MRK.mark_validate_bufname(bufname)

    local new_mark = MRK.mark_create(bufname)
    table.insert(MRK.mark_get_all(), new_mark)
    if config.notify.add then
      require('trident.util').info(("'%s' added"):format(vim.fn.fnamemodify(bufname, ':~')))
    end
  end

  MRK.mark_emit_changed()
end

function M.rm_file()
  local MRK = require('trident.mark')
  local bufname = MRK.mark_get_bufname()
  local idx = MRK.mark_get_index_of(bufname)

  if not MRK.mark_valid_index(idx) then
    return
  end
  MRK.mark_remove(idx)
  MRK.mark_emit_changed()
  if require('trident.config').notify.remove then
    require('trident.util').info(("'%s' removed"):format(vim.fn.fnamemodify(bufname, ':~')))
  end
end

function M.nav_file(id)
  local MRK = require('trident.mark')
  local idx = MRK.mark_get_index_of(id)
  if not MRK.mark_valid_index(idx) then
    return
  end

  local mark = MRK.mark_get_by_id(idx)
  local filename = vim.fs.normalize(mark.filename)
  local bufnr = MRK.mark_get_or_create_file(filename)
  local set_cursor = require('trident.config').always_set_cursor
    ---@diagnostic disable-next-line
    or not api.nvim_buf_is_loaded(bufnr)
  local old_bufnr = api.nvim_get_current_buf()

  ---@diagnostic disable-next-line
  api.nvim_set_current_buf(bufnr)
  api.nvim_set_option_value('buflisted', true, { buf = bufnr })

  if set_cursor and mark.row and mark.col then
    ---@diagnostic disable-next-line
    api.nvim_win_set_cursor(vim.fn.bufwinid(bufnr), { mark.row, mark.col })
  end

  local old_bufinfo = vim.fn.getbufinfo(old_bufnr)
  if type(old_bufinfo) == 'table' and #old_bufinfo >= 1 then
    old_bufinfo = old_bufinfo[1]
    local no_name = old_bufinfo.name == ''
    local one_line = old_bufinfo.linecount == 1
    local unchanged = old_bufinfo.changed == 0
    if no_name and one_line and unchanged then
      api.nvim_buf_delete(old_bufnr, {})
    end
  end
end

function M.nav_next()
  local MRK = require('trident.mark')
  local cur_idx = MRK.mark_get_current_index()
  local marks = MRK.mark_get_all()
  local len = marks and #marks or 0
  if cur_idx == nil then
    cur_idx = 1
  else
    cur_idx = cur_idx + 1
  end
  if cur_idx > len then
    cur_idx = 1
  end
  M.nav_file(cur_idx)
end

function M.nav_prev()
  local MRK = require('trident.mark')
  local cur_idx = MRK.mark_get_current_index()
  local marks = MRK.mark_get_all()
  local len = marks and #marks or 0
  if cur_idx == nil then
    cur_idx = len
  else
    cur_idx = cur_idx - 1
  end
  if cur_idx < 1 then
    cur_idx = len
  end
  M.nav_file(cur_idx)
end

function M.status()
  local MRK = require('trident.mark')
  return MRK.mark_get_index_of(MRK.mark_get_bufname())
end

function M.toggle_file()
  local MRK = require('trident.mark')
  local bufname = MRK.mark_get_bufname()
  local idx = MRK.mark_get_index_of(bufname)
  if not MRK.mark_valid_index(idx) then
    M.add_file()
  else
    M.rm_file()
  end
end

function M.toggle_branch(enable)
  local CFG = require('trident.config')
  local new_state
  if enable ~= nil then
    new_state = enable
  else
    new_state = not CFG.mark_branch
  end
  CFG.mark_branch = new_state
  if CFG.notify.mark_branch then
    require('trident.util').info(('mark branch %s'):format(new_state and 'enabled' or 'disabled'))
  end
end

function M.setup(opts)
  require('trident.config').setup(opts)
end

return M
