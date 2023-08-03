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
}

local api = vim.api

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
    vim.notify('cannot add trident to trident', vim.log.levels.ERROR, { title = 'Trident' })
    return false
  end
  if vim.tbl_contains(exft, ft) then
    vim.notify('this filetype is excluded', vim.log.levels.ERROR, { title = 'Trident' })
  end
  if bt ~= '' then
    vim.notify('can only add regular files to trident', vim.log.levels.ERROR, { title = 'Trident' })
    return false
  end
  return true
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

function Trident.add_file(name_or_id)
  if not H.filter_file() then
    return
  end
end

return Trident
