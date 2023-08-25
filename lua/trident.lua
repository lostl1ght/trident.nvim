local Trident = {}

--[[
{
  "projects": {
    "path-1-branch-a": {
      "marks": [
        {
          "col": 1,
          "row": 1,
          "filename": "file-1"
        },
        {
          "col": 5,
          "row": 4,
          "filename": "file-2"
        }
      ]
    },
    "path-1-branch-b": {
      "marks": [
        {
          "col": 2,
          "row": 3,
          "filename": "file-1"
        },
        {
          "col": 5,
          "row": 4,
          "filename": "file-3"
        },
      ]
    }
  },
}
--]]

local TridentAug = vim.api.nvim_create_augroup('TridentAug', {})
local M = {
  projects = {},
  bufnr = -1,
  winid = -1,
  pattern = '^/.-/.-/()',
  format = [[/%s/%s /%s]],
}

local api = vim.api
-- NOTE: update on stable
local uv = vim.uv or vim.loop

function M.menu_close()
  -- TODO: figure out confirm()
  M.window_close()
end

function M.window_close()
  api.nvim_win_close(M.winid, true)
  M.bufnr = -1
  M.winid = -1
end

function M.menu_select()
  local idx = vim.fn.line('.')
  M.menu_close()
  Trident.nav_file(idx)
end

function M.menu_on_write()
  M.mark_update_from_menu()
  M.mark_save_to_disk()
end

function M.menu_buffer_create()
  M.bufnr = api.nvim_create_buf(false, false)
  api.nvim_set_option_value('bufhidden', 'wipe', { buf = M.bufnr })
  api.nvim_set_option_value('filetype', 'trident', { buf = M.bufnr })
  api.nvim_set_option_value('buftype', 'acwrite', { buf = M.bufnr })

  local contents = M.line_get_contents()
  -- TODO: figure out icon highlights
  api.nvim_buf_set_lines(M.bufnr, 0, #contents, false, contents)
  api.nvim_buf_set_name(M.bufnr, 'trident-menu')

  api.nvim_buf_set_keymap(
    M.bufnr,
    'n',
    'q',
    '',
    { noremap = true, desc = 'Toggle menu', callback = Trident.toggle_menu }
  )
  api.nvim_buf_set_keymap(
    M.bufnr,
    'n',
    '<esc>',
    '',
    { noremap = true, desc = 'Toggle menu', callback = Trident.toggle_menu }
  )
  api.nvim_buf_set_keymap(
    M.bufnr,
    'n',
    '<cr>',
    '',
    { noremap = true, desc = 'Nav to file', callback = M.menu_select }
  )

  local function modified_callback()
    local modified = api.nvim_get_option_value('modified', { buf = M.bufnr })
    local border_hl = modified and 'TridentBorderModified' or 'TridentBorder'
    M.menu_update_highlight(M.winid, 'FloatBorder', border_hl)
  end
  api.nvim_create_autocmd('BufWriteCmd', {
    buffer = M.bufnr,
    callback = function()
      M.menu_on_write()
      local lines = api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
      if #lines == 1 and lines[1] == '' then
        lines = {}
      end
      local marks = M.mark_get_all()
      local total = marks and #marks or 1
      for i, line in ipairs(lines) do
        if line:match(M.pattern) == nil then
          local replacement = M.line_format(line, i, total)
          api.nvim_buf_set_lines(M.bufnr, i - 1, i, false, { replacement })
        end
      end
      api.nvim_set_option_value('modified', false, { buf = M.bufnr })
      modified_callback()
    end,
  })
  -- TODO: better modified tracking
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    buffer = M.bufnr,
    callback = modified_callback,
  })
  api.nvim_create_autocmd('BufLeave', {
    buffer = M.bufnr,
    once = true,
    nested = true,
    callback = Trident.toggle_menu,
  })

  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    buffer = M.bufnr,
    callback = M.menu_track_cursor,
  })
  api.nvim_set_option_value('modified', false, { buf = M.bufnr })
end

function M.menu_update_highlight(winid, new_from, new_to)
  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local winhl = api.nvim_get_option_value('winhighlight', { win = winid })
  local new_winhl, n_replace = winhl:gsub(replace_pattern, new_entry)
  if n_replace == 0 then
    new_winhl = new_winhl .. ',' .. new_entry
  end

  api.nvim_set_option_value('winhighlight', new_winhl, { win = winid })
end

M.menu_track_cursor = vim.schedule_wrap(function()
  local bufnr = M.bufnr
  local winid = M.winid
  if not api.nvim_win_is_valid(winid) then
    return
  end

  local cursor = api.nvim_win_get_cursor(winid)
  local l = M.menu_get_bufline(bufnr, cursor[1])

  local cur_offset = M.menu_match_line_offset(l)
  if cursor[2] < (cur_offset - 1) then
    cursor[2] = cur_offset - 1
    api.nvim_win_set_cursor(winid, cursor)
    -- Ensure icons are shown (may be not the case after horizontal scroll)
    api.nvim_cmd({ cmd = 'normal', bang = true, args = { '1000zh' } }, {})
  end
end)

function M.menu_get_bufline(bufnr, line)
  return api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
end

function M.menu_match_line_offset(l)
  if l == nil then
    return nil
  end
  return l:match(M.pattern) or 1
end

function M.menu_create_window()
  local window_cfg = {
    title = 'Trident',
    title_pos = 'center',
    style = 'minimal',
    noautocmd = true,
  }

  local user_cfg = {}
  local config = require('trident.config')
  for key, val in pairs(config.window) do
    if type(val) == 'function' then
      user_cfg[key] = val()
    else
      user_cfg[key] = val
    end
  end

  window_cfg = vim.tbl_extend('force', window_cfg, user_cfg)

  M.winid = api.nvim_open_win(M.bufnr, true, window_cfg)

  api.nvim_set_option_value('wrap', false, { win = M.winid })
  api.nvim_set_option_value('concealcursor', 'nvic', { win = M.winid })
  api.nvim_set_option_value('conceallevel', 3, { win = M.winid })
  api.nvim_win_call(M.winid, function()
    vim.fn.matchadd('Conceal', [[^/\d\+/]])
    vim.fn.matchadd('Conceal', [[^/\d\+/[^/]*\zs/\ze]])
  end)
end

function M.line_pad_number(n, total)
  local digits = 0

  while total > 0 do
    total = math.floor(total / 10)
    digits = digits + 1
  end
  local format = [[%0]] .. digits .. [[d]]
  return string.format(format, n)
end

function M.line_format(line, n, total)
  line = vim.fn.fnamemodify(line, ':~')
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  local icon
  if ok then
    icon = devicons.get_icon(line, vim.fn.fnamemodify(line, ':e'), { default = false })
  end
  return M.format:format(M.line_pad_number(n, total), (icon or ''), line)
end

function M.line_get_contents()
  local marks = M.mark_get_all()
  local contents = {}
  for i, v in ipairs(marks or {}) do
    local line = M.line_format(v.filename, i, #marks)
    table.insert(contents, line)
  end
  return contents
end

function M.mark_get_or_create_file(filename)
  local buf_exists = vim.fn.bufexists(filename) ~= 0
  if buf_exists then
    return vim.fn.bufnr(filename)
  end
  return vim.fn.bufadd(filename)
end

function M.mark_get_by_id(idx)
  local marks = M.mark_get_all()
  return marks[idx]
end

function M.mark_update_from_menu()
  local lines = api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
  local key = M.mark_get_key()
  local marks = M.mark_get_all()
  if #lines == 1 and lines[1] == '' then
    lines = {}
  end

  local new_marks = {}
  for _, line in ipairs(lines) do
    line = line:gsub(M.pattern, '')
    local idx = M.mark_get_index_of(line, marks)
    if M.mark_valid_index(idx) then
      table.insert(new_marks, marks[idx])
    else
      table.insert(new_marks, M.mark_create(line))
    end
  end
  M.projects[key].marks = new_marks
end

function M.mark_filter_file()
  local ft = api.nvim_get_option_value('filetype', { scope = 'local' })
  local bt = api.nvim_get_option_value('buftype', { scope = 'local' })
  local exft = require('trident.config').excluded_filetypes
  if ft == 'trident' then
    require('trident.util').error('cannot add trident to trident')
    return false
  end
  if bt ~= '' then
    require('trident.util').error('can only add regular files to trident')
    return false
  end
  if vim.tbl_contains(exft, ft) then
    require('trident.util').error('this filetype is excluded')
    return false
  end
  return true
end

function M.mark_get_bufname(bufnr)
  return vim.fs.normalize(api.nvim_buf_get_name(bufnr or 0))
end

function M.mark_branch_key()
  local branch
  local obj = vim.system({ 'git', 'rev-parse', '--abbrev-ref', 'HEAD' }, { text = true }):wait()
  branch = obj.stdout
  if branch == 'HEAD' then
    obj = vim.system({ 'git', 'rev-parse', '--short', 'HEAD' }, { text = true }):wait()
    branch = obj.stdout
  end
  if branch then
    return uv.cwd() .. ':' .. branch:gsub('\n', '')
  else
    return M.mark_project_key()
  end
end

function M.mark_project_key()
  return uv.cwd()
end

function M.mark_get_key()
  if require('trident.config').mark_branch then
    return M.mark_branch_key()
  else
    return M.mark_project_key()
  end
end

function M.mark_get_project()
  local key = M.mark_get_key()
  return M.projects[key]
end

function M.mark_get_all()
  local project = M.mark_get_project()
  return project and project.marks
end

function M.mark_get_index_of(item, marks)
  marks = marks or M.mark_get_all()
  if marks == nil then
    return nil
  end
  if type(item) == 'string' then
    local filename = vim.fs.normalize(item)

    for i, v in ipairs(marks) do
      if v.filename == filename then
        return i
      end
    end
    return nil
  end
  if item <= #marks and item >= 1 then
    return item
  end
  return nil
end

function M.mark_get_filename(idx)
  local marks = M.mark_get_all()
  return marks and marks[idx] and marks[idx].filename
end

function M.mark_valid_index(idx)
  if idx == nil then
    return false
  end

  local filename = M.mark_get_filename(idx)
  return filename ~= nil and filename ~= ''
end

function M.mark_validate_bufname(bufname)
  local valid = bufname ~= nil or bufname ~= ''
  if not valid then
    require('trident.util').error('cannot find a valid file name to mark')
  end
  return valid
end

function M.mark_create(filename)
  filename = vim.fs.normalize(filename)
  local buf_exists = vim.fn.bufexists(filename) ~= 0
  local cursor = buf_exists and api.nvim_win_get_cursor(0) or { 1, 0 }
  local marks = M.mark_get_all()
  if marks == nil then
    local project = M.mark_get_project()
    if project == nil then
      M.projects[M.mark_get_key()] = { marks = {} }
      marks = M.projects[M.mark_get_key()].marks
    end
  end
  return { filename = vim.fs.normalize(filename), row = cursor[1], col = cursor[2] }
end

function M.mark_emit_changed()
  if require('trident.config').save_on_change then
    M.mark_save_to_disk()
  end
end

function M.mark_remove(index)
  local marks = M.mark_get_all()
  table.remove(marks, index)
end

function M.mark_refresh()
  local key = M.mark_get_key()
  local current_project = {
    [key] = vim.deepcopy(M.projects[key]),
  }
  M.projects = nil

  local ok, on_disk_project = pcall(M.file_read_marks)
  if not ok then
    on_disk_project = {}
  end
  M.projects = vim.tbl_deep_extend('force', on_disk_project, current_project)
end

function M.mark_save_to_disk()
  M.mark_refresh()
  M.file_write_data()
end

function M.mark_get_current_index()
  return M.mark_get_index_of(M.mark_get_bufname())
end

function M.mark_update_cursor(id)
  local cursor = api.nvim_win_get_cursor(0)
  local mark = M.mark_get_by_id(id)
  mark.row = cursor[1]
  mark.col = cursor[2]
  M.mark_emit_changed()
end

function M.file_read_marks()
  local fd = assert(uv.fs_open(require('trident.config').data_path, 'r', 438))
  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, 0))
  assert(uv.fs_close(fd))
  ---@diagnostic disable-next-line
  return vim.json.decode(data)
end

function M.file_write_data()
  local fd = assert(uv.fs_open(require('trident.config').data_path, 'w', 438))
  assert(uv.fs_write(fd, vim.fn.json_encode(M.projects)))
  assert(uv.fs_close(fd))
end

function Trident.toggle_menu()
  if M.winid ~= -1 and api.nvim_win_is_valid(M.winid) then
    M.menu_close()
    return
  end
  M.menu_buffer_create()
  M.menu_create_window()
  require('trident.util').trigger_event('TridentWindowOpen', { bufnr = M.bufnr, winid = M.winid })
end

function Trident.add_file()
  if not M.mark_filter_file() then
    return
  end
  local bufname = M.mark_get_bufname()
  local idx = M.mark_get_index_of(bufname)
  local config = require('trident.config')
  if M.mark_valid_index(idx) then
    M.mark_update_cursor(idx)
    if config.notify.update then
      require('trident.util').info(("'%s' updated"):format(vim.fn.fnamemodify(bufname, ':~')))
    end
  else
    M.mark_validate_bufname(bufname)

    local new_mark = M.mark_create(bufname)
    table.insert(M.mark_get_all(), new_mark)
    if config.notify.add then
      require('trident.util').info(("'%s' added"):format(vim.fn.fnamemodify(bufname, ':~')))
    end
  end

  M.mark_emit_changed()
end

function Trident.rm_file()
  local bufname = M.mark_get_bufname()
  local idx = M.mark_get_index_of(bufname)

  if not M.mark_valid_index(idx) then
    return
  end
  M.mark_remove(idx)
  M.mark_emit_changed()
  if require('trident.config').notify.remove then
    require('trident.util').info(("'%s' removed"):format(vim.fn.fnamemodify(bufname, ':~')))
  end
end

function Trident.nav_file(id)
  local idx = M.mark_get_index_of(id)
  if not M.mark_valid_index(idx) then
    return
  end

  local mark = M.mark_get_by_id(idx)
  local filename = vim.fs.normalize(mark.filename)
  local bufnr = M.mark_get_or_create_file(filename)
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

function Trident.nav_next()
  local cur_idx = M.mark_get_current_index()
  local marks = M.mark_get_all()
  local len = marks and #marks or 0
  if cur_idx == nil then
    cur_idx = 1
  else
    cur_idx = cur_idx + 1
  end
  if cur_idx > len then
    cur_idx = 1
  end
  Trident.nav_file(cur_idx)
end

function Trident.nav_prev()
  local cur_idx = M.mark_get_current_index()
  local marks = M.mark_get_all()
  local len = marks and #marks or 0
  if cur_idx == nil then
    cur_idx = len
  else
    cur_idx = cur_idx - 1
  end
  if cur_idx < 1 then
    cur_idx = len
  end
  Trident.nav_file(cur_idx)
end

function Trident.status()
  return M.mark_get_index_of(M.mark_get_bufname())
end

function Trident.toggle_file()
  local bufname = M.mark_get_bufname()
  local idx = M.mark_get_index_of(bufname)
  if not M.mark_valid_index(idx) then
    Trident.add_file()
  else
    Trident.rm_file()
  end
end

function Trident.toggle_branch(enable)
  local config = require('trident.config')
  local new_state
  if enable ~= nil then
    new_state = enable
  else
    new_state = not config.mark_branch
  end
  config.mark_branch = new_state
  if config.notify.mark_branch then
    require('trident.util').info(('mark branch %s'):format(new_state and 'enabled' or 'disabled'))
  end
end

function Trident.setup(opts)
  require('trident.config').setup(opts)
end

function Trident._must_set()
  local ok, on_disk_projects = pcall(M.file_read_marks)
  if not ok then
    on_disk_projects = {}
  end
  M.projects = on_disk_projects
  local function update_cursor(bufnr)
    local bufname = M.mark_get_bufname(bufnr)
    local idx = M.mark_get_index_of(bufname)
    if M.mark_valid_index(idx) then
      M.mark_update_cursor(idx)
    end
  end
  api.nvim_create_autocmd('VimLeavePre', {
    group = TridentAug,
    callback = function()
      update_cursor()
      M.mark_save_to_disk()
    end,
  })
  api.nvim_create_autocmd('BufLeave', {
    group = TridentAug,
    callback = function(data)
      if require('trident.config').always_set_cursor then
        update_cursor(data.buf)
      end
    end,
  })
  local did_set = false
  require('editorconfig').properties.trident_mark_branch = function(_, val, _)
    if not did_set then
      local stringboolean = {
        ['true'] = true,
        ['false'] = false,
      }
      Trident.toggle_branch(stringboolean[val])
      did_set = true
    end
  end
end

return Trident
