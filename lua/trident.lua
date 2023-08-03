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
  "settings": {
    "mark_branch": true
  }
}
--]]

local H = {
  bufnr = -1,
  winid = -1,
  config = {
    save_on_change = true,
    mark_branch = true,
    excluded_filetypes = {},
  },
  projects = {},
}

local api = vim.api

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
  -- TODO: add select
  vim.notify('idx ' .. idx)
end

function H.on_mene_save()
  -- TODO: save
  vim.notify('save')
end

function H.create_buffer()
  H.bufnr = api.nvim_create_buf(false, false)
  api.nvim_set_option_value('bufhidden', 'wipe', { buf = H.bufnr })
  api.nvim_set_option_value('filetype', 'trident', { buf = H.bufnr })
  api.nvim_set_option_value('buftype', 'acwrite', { buf = H.bufnr })

  local contents = {
    'line 1',
    'line 2',
  }
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
  api.nvim_create_autocmd('BufWriteCmd', {
    buffer = H.bufnr,
    callback = H.on_mene_save,
  })
  api.nvim_create_autocmd('BufModifiedSet', {
    buffer = H.bufnr,
    callback = function()
      api.nvim_set_option_value('modified', false, { buf = H.bufnr })
    end,
  })
  api.nvim_create_autocmd('BufLeave', {
    buffer = H.bufnr,
    once = true,
    nested = true,
    callback = Trident.toggle_menu,
  })
  if H.config.save_on_change then
    api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      buffer = H.bufnr,
      callback = H.on_mene_save,
    })
  end
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
    -- NOTE: delete on stable
    return (vim.uv and vim.uv.cwd or vim.loop.cwd)() .. ':' .. branch
  else
    return H.project_key()
  end
end

function H.project_key()
  return (vim.uv and vim.uv.cwd or vim.loop.cwd)()
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

function H.get_index_of(item)
  local filename = vim.fs.normalize(item)
  local marks = H.get_marks()
  if marks == nil then
    return nil
  end

  for i, v in ipairs(marks) do
    if v.filename == filename then
      return i
    end
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
  local cursor = api.nvim_win_get_cursor(0)
  local marks = H.get_marks()
  if marks == nil then
    local project = H.get_project()
    if project == nil then
      H.projects[H.get_mark_key()] = { marks = {} }
      marks = H.projects[H.get_mark_key()].marks
    end
  end
  table.insert(marks, { filename = filename, row = cursor[1], col = cursor[2] })
end

function H.emit_changed()
  H.info(vim.inspect(H.projects))
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

return Trident
