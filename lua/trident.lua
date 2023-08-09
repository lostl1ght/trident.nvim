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
local default_height = 10
local function default_width()
  return math.floor(vim.api.nvim_get_option_value('columns', { scope = 'global' }) * 0.9)
end
local H = {
  bufnr = -1,
  winid = -1,
  config = {
    data_path = vim.fs.normalize(vim.fn.stdpath('data') .. '/trident.json'),
    mark_branch = true,
    notify = {
      mark_branch = true,
      remove = true,
      add = true,
      update = true,
    },
    always_set_cursor = true,
    save_on_change = true,
    excluded_filetypes = {},
    window = {
      height = default_height,
      width = default_width,
      row = function()
        local lines = vim.api.nvim_get_option_value('lines', { scope = 'global' })
        return math.floor((lines - default_height) / 2 - 1)
      end,
      col = function()
        local columns = vim.api.nvim_get_option_value('columns', { scope = 'global' })
        return math.floor((columns - default_width()) / 2)
      end,
      border = 'single',
      relative = 'editor',
    },
  },
  projects = {},
  pattern = '^/.-/.-/()',
  format = [[/%s/%s /%s]],
}

local api = vim.api
-- NOTE: update on stable
local uv = vim.uv or vim.loop

---@param msg any
---@param level integer
function H.notify(msg, level)
  vim.notify(msg, level, { title = 'Trident' })
end

function H.error(msg)
  H.notify(msg, vim.log.levels.ERROR)
end

function H.info(msg)
  H.notify(msg, vim.log.levels.INFO)
end

function H.debug(msg)
  H.notify(msg, vim.log.levels.DEBUG)
end

function H.menu_close()
  -- TODO: figure out confirm()
  H.window_close()
end

function H.window_close()
  api.nvim_win_close(H.winid, true)
  H.bufnr = -1
  H.winid = -1
end

function H.menu_select()
  local idx = vim.fn.line('.')
  H.menu_close()
  Trident.nav_file(idx)
end

function H.menu_on_write()
  H.mark_update_from_menu()
  H.mark_save_to_disk()
end

function H.menu_buffer_create()
  H.bufnr = api.nvim_create_buf(false, false)
  api.nvim_set_option_value('bufhidden', 'wipe', { buf = H.bufnr })
  api.nvim_set_option_value('filetype', 'trident', { buf = H.bufnr })
  api.nvim_set_option_value('buftype', 'acwrite', { buf = H.bufnr })

  local contents = H.line_get_contents()
  -- TODO: figure out icon highlights
  api.nvim_buf_set_lines(H.bufnr, 0, #contents, false, contents)
  api.nvim_buf_set_name(H.bufnr, 'trident-menu')

  api.nvim_buf_set_keymap(
    H.bufnr,
    'n',
    'q',
    '',
    { noremap = true, desc = 'Toggle menu', callback = Trident.toggle_menu }
  )
  api.nvim_buf_set_keymap(
    H.bufnr,
    'n',
    '<esc>',
    '',
    { noremap = true, desc = 'Toggle menu', callback = Trident.toggle_menu }
  )
  api.nvim_buf_set_keymap(
    H.bufnr,
    'n',
    '<cr>',
    '',
    { noremap = true, desc = 'Nav to file', callback = H.menu_select }
  )

  local function modified_callback()
    local modified = api.nvim_get_option_value('modified', { buf = H.bufnr })
    local border_hl = modified and 'TridentBorderModified' or 'TridentBorder'
    H.menu_update_highlight(H.winid, 'FloatBorder', border_hl)
  end
  api.nvim_create_autocmd('BufWriteCmd', {
    buffer = H.bufnr,
    callback = function()
      H.menu_on_write()
      local lines = api.nvim_buf_get_lines(H.bufnr, 0, -1, false)
      if #lines == 1 and lines[1] == '' then
        lines = {}
      end
      local marks = H.mark_get_all()
      local total = marks and #marks or 1
      for i, line in ipairs(lines) do
        if line:match(H.pattern) == nil then
          local replacement = H.line_format(line, i, total)
          api.nvim_buf_set_lines(H.bufnr, i - 1, i, false, { replacement })
        end
      end
      api.nvim_set_option_value('modified', false, { buf = H.bufnr })
      modified_callback()
    end,
  })
  -- TODO: better modified tracking
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    buffer = H.bufnr,
    callback = modified_callback,
  })
  api.nvim_create_autocmd('BufLeave', {
    buffer = H.bufnr,
    once = true,
    nested = true,
    callback = Trident.toggle_menu,
  })

  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    buffer = H.bufnr,
    callback = H.menu_track_cursor,
  })
  api.nvim_set_option_value('modified', false, { buf = H.bufnr })
end

function H.menu_update_highlight(winid, new_from, new_to)
  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local winhl = api.nvim_get_option_value('winhighlight', { win = winid })
  local new_winhl, n_replace = winhl:gsub(replace_pattern, new_entry)
  if n_replace == 0 then
    new_winhl = new_winhl .. ',' .. new_entry
  end

  api.nvim_set_option_value('winhighlight', new_winhl, { win = winid })
end

H.menu_track_cursor = vim.schedule_wrap(function()
  local bufnr = H.bufnr
  local winid = H.winid
  if not api.nvim_win_is_valid(winid) then
    return
  end

  local cursor = api.nvim_win_get_cursor(winid)
  local l = H.menu_get_bufline(bufnr, cursor[1])

  local cur_offset = H.menu_match_line_offset(l)
  if cursor[2] < (cur_offset - 1) then
    cursor[2] = cur_offset - 1
    api.nvim_win_set_cursor(winid, cursor)
    -- Ensure icons are shown (may be not the case after horizontal scroll)
    api.nvim_cmd({ cmd = 'normal', bang = true, args = { '1000zh' } }, {})
  end
end)

function H.menu_get_bufline(bufnr, line)
  return api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
end

function H.menu_match_line_offset(l)
  if l == nil then
    return nil
  end
  return l:match(H.pattern) or 1
end

function H.menu_create_window()
  local window_cfg = {
    title = 'Trident',
    title_pos = 'center',
    style = 'minimal',
    noautocmd = true,
  }

  local user_cfg = {}
  for key, val in pairs(H.config.window) do
    if type(val) == 'function' then
      user_cfg[key] = val()
    else
      user_cfg[key] = val
    end
  end

  window_cfg = vim.tbl_extend('force', window_cfg, user_cfg)

  H.winid = api.nvim_open_win(H.bufnr, true, window_cfg)

  api.nvim_set_option_value('wrap', false, { win = H.winid })
  api.nvim_set_option_value('concealcursor', 'nvic', { win = H.winid })
  api.nvim_set_option_value('conceallevel', 3, { win = H.winid })
  api.nvim_win_call(H.winid, function()
    vim.fn.matchadd('Conceal', [[^/\d\+/]])
    vim.fn.matchadd('Conceal', [[^/\d\+/[^/]*\zs/\ze]])
  end)
end

function H.line_pad_number(n, total)
  local digits = 0

  while total > 0 do
    total = math.floor(total / 10)
    digits = digits + 1
  end
  local format = [[%0]] .. digits .. [[d]]
  return string.format(format, n)
end

function H.line_format(line, n, total)
  line = vim.fn.fnamemodify(line, ':~')
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  local icon
  if ok then
    icon = devicons.get_icon(line, vim.fn.fnamemodify(line, ':e'), { default = false })
  end
  return H.format:format(H.line_pad_number(n, total), (icon or ''), line)
end

function H.line_get_contents()
  local marks = H.mark_get_all()
  local contents = {}
  for i, v in ipairs(marks or {}) do
    local line = H.line_format(v.filename, i, #marks)
    table.insert(contents, line)
  end
  return contents
end

function H.mark_get_or_create_file(filename)
  local buf_exists = vim.fn.bufexists(filename) ~= 0
  if buf_exists then
    return vim.fn.bufnr(filename)
  end
  return vim.fn.bufadd(filename)
end

function H.mark_get_by_id(idx)
  local marks = H.mark_get_all()
  return marks[idx]
end

function H.mark_update_from_menu()
  local lines = api.nvim_buf_get_lines(H.bufnr, 0, -1, false)
  local key = H.mark_get_key()
  local marks = H.mark_get_all()
  if #lines == 1 and lines[1] == '' then
    lines = {}
  end

  local new_marks = {}
  for _, line in ipairs(lines) do
    line = line:gsub(H.pattern, '')
    local idx = H.mark_get_index_of(line, marks)
    if H.mark_valid_index(idx) then
      table.insert(new_marks, marks[idx])
    else
      table.insert(new_marks, H.mark_create(line))
    end
  end
  H.projects[key].marks = new_marks
end

function H.mark_filter_file()
  local ft = api.nvim_get_option_value('filetype', { scope = 'local' })
  local bt = api.nvim_get_option_value('buftype', { scope = 'local' })
  local exft = H.config.excluded_filetypes
  if ft == 'trident' then
    H.error('cannot add trident to trident')
    return false
  end
  if bt ~= '' then
    H.error('can only add regular files to trident')
    return false
  end
  if vim.tbl_contains(exft, ft) then
    H.error('this filetype is excluded')
    return false
  end
  return true
end

function H.mark_get_bufname(bufnr)
  return vim.fs.normalize(api.nvim_buf_get_name(bufnr or 0))
end

function H.mark_branch_key()
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
    return H.mark_project_key()
  end
end

function H.mark_project_key()
  return uv.cwd()
end

function H.mark_get_key()
  if H.config.mark_branch then
    return H.mark_branch_key()
  else
    return H.mark_project_key()
  end
end

function H.mark_get_project()
  local key = H.mark_get_key()
  return H.projects[key]
end

function H.mark_get_all()
  local project = H.mark_get_project()
  return project and project.marks
end

function H.mark_get_index_of(item, marks)
  marks = marks or H.mark_get_all()
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

function H.mark_get_filename(idx)
  local marks = H.mark_get_all()
  return marks and marks[idx] and marks[idx].filename
end

function H.mark_valid_index(idx)
  if idx == nil then
    return false
  end

  local filename = H.mark_get_filename(idx)
  return filename ~= nil and filename ~= ''
end

function H.mark_validate_bufname(bufname)
  local valid = bufname ~= nil or bufname ~= ''
  if not valid then
    H.error('cannot find a valid file name to mark')
  end
  return valid
end

function H.mark_create(filename)
  filename = vim.fs.normalize(filename)
  local buf_exists = vim.fn.bufexists(filename) ~= 0
  local cursor = buf_exists and api.nvim_win_get_cursor(0) or { 1, 0 }
  local marks = H.mark_get_all()
  if marks == nil then
    local project = H.mark_get_project()
    if project == nil then
      H.projects[H.mark_get_key()] = { marks = {} }
      marks = H.projects[H.mark_get_key()].marks
    end
  end
  return { filename = vim.fs.normalize(filename), row = cursor[1], col = cursor[2] }
end

function H.mark_emit_changed()
  if H.config.save_on_change then
    H.mark_save_to_disk()
  end
end

function H.mark_remove(index)
  local marks = H.mark_get_all()
  table.remove(marks, index)
end

function H.mark_refresh()
  local key = H.mark_get_key()
  local current_project = {
    [key] = vim.deepcopy(H.projects[key]),
  }
  H.projects = nil

  local ok, on_disk_project = pcall(H.file_read_marks)
  if not ok then
    on_disk_project = {}
  end
  H.projects = vim.tbl_deep_extend('force', on_disk_project, current_project)
end

function H.mark_save_to_disk()
  H.mark_refresh()
  H.file_write_data()
end

function H.mark_get_current_index()
  return H.mark_get_index_of(H.mark_get_bufname())
end

function H.mark_update_cursor(id)
  local cursor = api.nvim_win_get_cursor(0)
  local mark = H.mark_get_by_id(id)
  mark.row = cursor[1]
  mark.col = cursor[2]
  if H.config.save_on_change then
    H.mark_save_to_disk()
  end
end

function H.file_read_marks()
  local fd = assert(uv.fs_open(H.config.data_path, 'r', 438))
  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, 0))
  assert(uv.fs_close(fd))
  ---@diagnostic disable-next-line
  return vim.json.decode(data)
end

function H.file_write_data()
  local fd = assert(uv.fs_open(H.config.data_path, 'w', 438))
  assert(uv.fs_write(fd, vim.fn.json_encode(H.projects)))
  assert(uv.fs_close(fd))
end

function H.trigger_event(event, data)
  api.nvim_exec_autocmds('User', { pattern = event, data = data })
end

function Trident.toggle_menu()
  if H.winid ~= -1 and api.nvim_win_is_valid(H.winid) then
    H.menu_close()
    return
  end
  H.menu_buffer_create()
  H.menu_create_window()
  H.trigger_event('TridentWindowOpen', { bufnr = H.bufnr, winid = H.winid })
end

function Trident.add_file()
  if not H.mark_filter_file() then
    return
  end
  local bufname = H.mark_get_bufname()
  local idx = H.mark_get_index_of(bufname)
  if H.mark_valid_index(idx) then
    H.mark_update_cursor(idx)
    if H.config.notify.update then
      H.info(("'%s' updated"):format(vim.fn.fnamemodify(bufname, ':~')))
    end
  else
    H.mark_validate_bufname(bufname)

    local new_mark = H.mark_create(bufname)
    table.insert(H.mark_get_all(), new_mark)
    if H.config.notify.add then
      H.info(("'%s' added"):format(vim.fn.fnamemodify(bufname, ':~')))
    end
  end

  H.mark_emit_changed()
end

function Trident.rm_file()
  local bufname = H.mark_get_bufname()
  local idx = H.mark_get_index_of(bufname)

  if not H.mark_valid_index(idx) then
    return
  end
  H.mark_remove(idx)
  H.mark_emit_changed()
  if H.config.notify.remove then
    H.info(("'%s' removed"):format(vim.fn.fnamemodify(bufname, ':~')))
  end
end

function Trident.nav_file(id)
  local idx = H.mark_get_index_of(id)
  if not H.mark_valid_index(idx) then
    return
  end

  local mark = H.mark_get_by_id(idx)
  local filename = vim.fs.normalize(mark.filename)
  local bufnr = H.mark_get_or_create_file(filename)
  ---@diagnostic disable-next-line
  local set_cursor = H.config.always_set_cursor or not api.nvim_buf_is_loaded(bufnr)
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
  local cur_idx = H.mark_get_current_index()
  local marks = H.mark_get_all()
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
  local cur_idx = H.mark_get_current_index()
  local marks = H.mark_get_all()
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
  return H.mark_get_index_of(H.mark_get_bufname())
end

function Trident.toggle_file()
  local bufname = H.mark_get_bufname()
  local idx = H.mark_get_index_of(bufname)
  if not H.mark_valid_index(idx) then
    Trident.add_file()
  else
    Trident.rm_file()
  end
end

function Trident.toggle_branch(enable)
  local new_state
  if enable ~= nil then
    new_state = enable
  else
    new_state = not H.config.mark_branch
  end
  H.config.mark_branch = new_state
  if H.config.notify.mark_branch then
    H.info(('mark branch %s'):format(new_state and 'enabled' or 'disabled'))
  end
end

function Trident.setup(opts)
  H.config = vim.tbl_deep_extend('force', H.config, opts or {})
end

function Trident._must_set()
  local ok, on_disk_projects = pcall(H.file_read_marks)
  if not ok then
    on_disk_projects = {}
  end
  H.projects = on_disk_projects
  local function update_cursor(bufnr)
    local bufname = H.mark_get_bufname(bufnr)
    local idx = H.mark_get_index_of(bufname)
    if H.mark_valid_index(idx) then
      H.mark_update_cursor(idx)
    end
  end
  api.nvim_create_autocmd('VimLeavePre', {
    group = TridentAug,
    callback = function()
      update_cursor()
      H.mark_save_to_disk()
    end,
  })
  api.nvim_create_autocmd('BufLeave', {
    group = TridentAug,
    callback = function(data)
      if H.config.always_set_cursor then
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
