local api = vim.api

local ok, on_disk_projects = pcall(require('trident.file').file_read_marks)
if not ok then
  on_disk_projects = {}
end
require('trident.projects').projects = on_disk_projects
local function update_cursor(bufnr)
  local MRK = require('trident.mark')
  local bufname = MRK.mark_get_bufname(bufnr)
  local idx = MRK.mark_get_index_of(bufname)
  if MRK.mark_valid_index(idx) then
    MRK.mark_update_cursor(idx)
  end
end
local TridentAug = vim.api.nvim_create_augroup('TridentAug', {})
api.nvim_create_autocmd('VimLeavePre', {
  group = TridentAug,
  callback = function()
    update_cursor()
    local MRK = require('trident.mark')
    MRK.mark_save_to_disk()
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
    require('trident').toggle_branch(stringboolean[val])
    did_set = true
  end
end
