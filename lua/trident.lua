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

local H = {
  bufnr = -1,
  winid = -1,
  config = {
    mark_branch = true,
    excluded_filetypes = {},
    data_path = vim.fs.normalize(vim.fn.stdpath('data') .. '/trident.json'),
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

function H.close_menu()
  -- save marks
  api.nvim_win_close(H.winid, true)
  H.bufnr = -1
  H.winid = -1
end

function H.select_menu_item()
  local idx = vim.fn.line('.')
  H.close_menu()
  Trident.nav_file(idx)
end

function H.get_or_create_buffer(filename)
  local buf_exists = vim.fn.bufexists(filename) ~= 0
  if buf_exists then
    return vim.fn.bufnr(filename)
  end
  return vim.fn.bufadd(filename)
end

function H.get_mark(idx)
  local marks = H.get_marks()
  return marks[idx]
end

function H.update_from_menu()
  local lines = api.nvim_buf_get_lines(H.bufnr, 0, -1, false)
  local key = H.get_mark_key()
  local marks = H.get_marks()
  if #lines == 1 and lines[1] == '' or marks == nil then
    return
  end

  local new_marks = {}
  for _, line in ipairs(lines) do
    line = line:gsub(H.pattern, '')
    local idx = H.get_index_of(line, marks)
    if H.valid_index(idx) then
      table.insert(new_marks, marks[idx])
    else
      H.create_mark(line)
    end
  end
  H.projects[key].marks = new_marks
end

function H.on_menu_save()
  H.update_from_menu()
  H.save()
end

function H.pad_number(n, total)
  local digits = 0

  while total > 0 do
    total = math.floor(total / 10)
    digits = digits + 1
  end
  local format = [[%0]] .. digits .. [[d]]
  return string.format(format, n)
end

function H.format_line(line, n, total)
  line = vim.fn.fnamemodify(line, ':~')
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  local icon
  if ok then
    icon = devicons.get_icon(line, vim.fn.fnamemodify(line, ':e'), { default = false })
  end
  return H.format:format(H.pad_number(n, total), (icon or ''), line)
end

function H.get_contents()
  local marks = H.get_marks()
  local contents = {}
  for i, v in ipairs(marks or {}) do
    local line = H.format_line(v.filename, i, #marks)
    table.insert(contents, line)
  end
  return contents
end

function H.create_buffer()
  H.bufnr = api.nvim_create_buf(false, false)
  api.nvim_set_option_value('bufhidden', 'wipe', { buf = H.bufnr })
  api.nvim_set_option_value('filetype', 'trident', { buf = H.bufnr })
  api.nvim_set_option_value('buftype', 'acwrite', { buf = H.bufnr })

  local contents = H.get_contents()
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
    { noremap = true, desc = 'Nav to file', callback = H.select_menu_item }
  )

  local function modified_callback()
    local modified = api.nvim_get_option_value('modified', { buf = H.bufnr })
    local border_hl = modified and 'TridentBorderModified' or 'TridentBorder'
    H.window_update_highlight(H.winid, 'FloatBorder', border_hl)
  end
  api.nvim_create_autocmd('BufWriteCmd', {
    buffer = H.bufnr,
    callback = function()
      H.on_menu_save()
      local lines = api.nvim_buf_get_lines(H.bufnr, 0, -1, false)
      if #lines == 1 and lines[1] == '' then
        return
      end
      local marks = H.get_marks()
      local total = marks and #marks or 1
      for i, line in ipairs(lines) do
        if line:match(H.pattern) == nil then
          local replacement = H.format_line(line, i, total)
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
    callback = H.view_track_cursor,
  })
  api.nvim_set_option_value('modified', false, { buf = H.bufnr })
end

function H.window_update_highlight(winid, new_from, new_to)
  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local winhl = api.nvim_get_option_value('winhighlight', { win = winid })
  local new_winhl, n_replace = winhl:gsub(replace_pattern, new_entry)
  if n_replace == 0 then
    new_winhl = new_winhl .. ',' .. new_entry
  end

  api.nvim_set_option_value('winhighlight', new_winhl, { win = winid })
end

H.view_track_cursor = vim.schedule_wrap(function()
  local bufnr = H.bufnr
  local winid = H.winid
  if not api.nvim_win_is_valid(winid) then
    return
  end

  local cursor = api.nvim_win_get_cursor(winid)
  local l = H.get_bufline(bufnr, cursor[1])

  local cur_offset = H.match_line_offset(l)
  if cursor[2] < (cur_offset - 1) then
    cursor[2] = cur_offset - 1
    api.nvim_win_set_cursor(winid, cursor)
    -- Ensure icons are shown (may be not the case after horizontal scroll)
    api.nvim_cmd({ cmd = 'normal', bang = true, args = { '1000zh' } }, {})
  end
end)

function H.get_bufline(bufnr, line)
  return api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
end

function H.match_line_offset(l)
  if l == nil then
    return nil
  end
  return l:match(H.pattern) or 1
end

function H.create_window()
  local lines = api.nvim_get_option_value('lines', { scope = 'global' })
  local columns = api.nvim_get_option_value('columns', { scope = 'global' })

  local width = math.floor(columns * 0.9)
  local height = 10
  local border = 'single'

  H.winid = api.nvim_open_win(H.bufnr, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((lines - height) / 2 - 1),
    col = math.floor((columns - width) / 2),
    border = border,
    title = 'Trident',
    title_pos = 'center',
    style = 'minimal',
    noautocmd = true,
  })

  api.nvim_set_option_value('wrap', false, { win = H.winid })
  api.nvim_set_option_value('concealcursor', 'nvic', { win = H.winid })
  api.nvim_set_option_value('conceallevel', 3, { win = H.winid })
  api.nvim_win_call(H.winid, function()
    vim.fn.matchadd('Conceal', [[^/\d\+/]])
    vim.fn.matchadd('Conceal', [[^/\d\+/[^/]*\zs/\ze]])
  end)
end

function H.trigger_event(event, data)
  api.nvim_exec_autocmds('User', { pattern = event, data = data })
end

function H.filter_file()
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

function H.get_bufname()
  return vim.fs.normalize(api.nvim_buf_get_name(0))
end

function H.branch_key()
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
    return H.project_key()
  end
end

function H.project_key()
  return uv.cwd()
end

function H.get_mark_key()
  if H.config.mark_branch then
    return H.branch_key()
  else
    return H.project_key()
  end
end

function H.get_project()
  local key = H.get_mark_key()
  return H.projects[key]
end

function H.get_marks()
  local project = H.get_project()
  return project and project.marks
end

function H.get_index_of(item, marks)
  marks = marks or H.get_marks()
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

function H.get_marked_filename(idx)
  local marks = H.get_marks()
  return marks and marks[idx] and marks[idx].filename
end

function H.valid_index(idx)
  if idx == nil then
    return false
  end

  local filename = H.get_marked_filename(idx)
  return filename ~= nil and filename ~= ''
end

function H.validate_bufname(bufname)
  local valid = bufname ~= nil or bufname ~= ''
  if not valid then
    H.error('cannot find a valid file name to mark')
  end
  return valid
end

function H.create_mark(filename)
  filename = vim.fs.normalize(filename)
  local buf_exists = vim.fn.bufexists(filename) ~= 0
  local cursor = buf_exists and api.nvim_win_get_cursor(0) or { 1, 0 }
  local marks = H.get_marks()
  if marks == nil then
    local project = H.get_project()
    if project == nil then
      H.projects[H.get_mark_key()] = { marks = {} }
      marks = H.projects[H.get_mark_key()].marks
    end
  end
  table.insert(marks, { filename = vim.fs.normalize(filename), row = cursor[1], col = cursor[2] })
end

function H.emit_changed()
  H.save()
end

function H.remove_mark(index)
  local marks = H.get_marks()
  table.remove(marks, index)
end

function H.read_data()
  local fd = assert(uv.fs_open(H.config.data_path, 'r', 438))
  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, 0))
  assert(uv.fs_close(fd))
  ---@diagnostic disable-next-line
  return vim.json.decode(data)
end

function H.refresh()
  local key = H.get_mark_key()
  local current_project = {
    [key] = vim.deepcopy(H.projects[key]),
  }
  H.projects = nil

  local ok, on_disk_project = pcall(H.read_data)
  if not ok then
    on_disk_project = {}
  end
  H.projects = vim.tbl_deep_extend('force', on_disk_project, current_project)
end

function H.write_data()
  local fd = assert(uv.fs_open(H.config.data_path, 'w', 438))
  assert(uv.fs_write(fd, vim.fn.json_encode(H.projects)))
  assert(uv.fs_close(fd))
end

function H.save()
  H.refresh()
  H.write_data()
end

function Trident.toggle_menu()
  if H.winid ~= -1 and api.nvim_win_is_valid(H.winid) then
    H.close_menu()
    return
  end
  H.create_buffer()
  H.create_window()
  H.trigger_event('TridentWindowOpen', { bufnr = H.bufnr, winid = H.winid })
end

function Trident.add_file()
  if not H.filter_file() then
    return
  end
  local bufname = H.get_bufname()
  if H.valid_index(H.get_index_of(bufname)) then
    return
  end

  H.validate_bufname(bufname)

  H.create_mark(bufname)
  H.emit_changed()
end

function Trident.rm_file()
  local bufname = H.get_bufname()
  local idx = H.get_index_of(bufname)

  if not H.valid_index(idx) then
    return
  end
  H.remove_mark(idx)
  H.emit_changed()
end

function Trident.nav_file(id)
  local idx = H.get_index_of(id)
  if not H.valid_index(idx) then
    return
  end

  local mark = H.get_mark(idx)
  local filename = vim.fs.normalize(mark.filename)
  local bufnr = H.get_or_create_buffer(filename)
  ---@diagnostic disable-next-line
  local set_row = not api.nvim_buf_is_loaded(bufnr)
  local old_bufnr = api.nvim_get_current_buf()

  ---@diagnostic disable-next-line
  api.nvim_set_current_buf(bufnr)
  api.nvim_set_option_value('buflisted', true, { buf = bufnr })

  if set_row and mark.row and mark.col then
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

function Trident.setup(opts)
  local ok, on_disk_project = pcall(H.read_data)
  if not ok then
    on_disk_project = {}
  end
  H.projects = on_disk_project
end

return Trident
