--[[
{
  "path-1:branch-a": {
    "marks": [
      {
        "col": 1,
        "row": 1,
        "filename": "file-1"
      },
      {
        "col": 2,
        "row": 2,
        "filename": "file-2"
      }
    ]
  },
  "path-1:branch-b": {
    "marks": [
      {
        "col": 3,
        "row": 3,
        "filename": "file-1"
      },
      {
        "col": 4,
        "row": 4,
        "filename": "file-3"
      }
    ]
  }
}
]]

local M = {
  projects = {},
}

local api = vim.api
local uv = vim.uv or vim.loop

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
  return require'trident.projects'.projects[key]
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
      local PRJ = require('trident.projects')
      PRJ.projects[M.mark_get_key()] = { marks = {} }
      marks = PRJ.projects[M.mark_get_key()].marks
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
  local PRJ = require('trident.projects')
  local current_project = {
    [key] = vim.deepcopy(PRJ.projects[key]),
  }
  PRJ.projects = nil

  local ok, on_disk_project = pcall(require('trident.file').file_read_marks)
  if not ok then
    on_disk_project = {}
  end
  PRJ.projects = vim.tbl_deep_extend('force', on_disk_project, current_project)
end

function M.mark_save_to_disk()
  M.mark_refresh()
  require('trident.file').file_write_data()
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

return M
