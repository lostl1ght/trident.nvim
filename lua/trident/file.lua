local M = {}

local uv = vim.uv or vim.loop

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
  assert(uv.fs_write(fd, vim.fn.json_encode(require('trident.projects').projects)))
  assert(uv.fs_close(fd))
end

return M
