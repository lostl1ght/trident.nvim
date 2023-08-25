local M = {
  bufnr = -1,
  winid = -1,
  pattern = '^/.-/.-/()',
  format = [[/%s/%s /%s]],
}

local api = vim.api

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
  require('trident').nav_file(idx)
end

function M.menu_on_write()
  local MRK = require('trident.mark')
  M.menu_update_from()
  MRK.mark_save_to_disk()
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
    { noremap = true, desc = 'Toggle menu', callback = M.menu_close }
  )
  api.nvim_buf_set_keymap(
    M.bufnr,
    'n',
    '<esc>',
    '',
    { noremap = true, desc = 'Toggle menu', callback = M.menu_close }
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
      local marks = require('trident.mark').mark_get_all()
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
    callback = M.menu_close,
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

function M.menu_update_from()
  local lines = api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
  local MRK = require('trident.mark')
  local key = MRK.mark_get_key()
  local marks = MRK.mark_get_all()
  if #lines == 1 and lines[1] == '' then
    lines = {}
  end

  local new_marks = {}
  for _, line in ipairs(lines) do
    line = line:gsub(M.pattern, '')
    local idx = MRK.mark_get_index_of(line, marks)
    if MRK.mark_valid_index(idx) then
      table.insert(new_marks, marks[idx])
    else
      table.insert(new_marks, MRK.mark_create(line))
    end
  end
  require('trident.projects').projects[key].marks = new_marks
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
  local marks = require('trident.mark').mark_get_all()
  local contents = {}
  for i, v in ipairs(marks or {}) do
    local line = M.line_format(v.filename, i, #marks)
    table.insert(contents, line)
  end
  return contents
end

return M
