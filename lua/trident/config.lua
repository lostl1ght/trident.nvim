local default_height = 10
local function default_width()
  return math.floor(vim.api.nvim_get_option_value('columns', { scope = 'global' }) * 0.9)
end

local M = {
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
        local height = require('trident.config').window.height
        if type(height) == 'function' then
          height = height()
        end
        return math.floor((lines - height) / 2 - 1)
      end,
      col = function()
        local columns = vim.api.nvim_get_option_value('columns', { scope = 'global' })
        local width = require('trident.config').window.width
        if type(width) == 'function' then
          width = width()
        end
        return math.floor((columns - width) / 2)
      end,
      border = 'single',
      relative = 'editor',
    },
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts)
end

setmetatable(M, {
  __index = function(self, key)
    if key ~= 'setup' then
      return self.config[key]
    end
    return self[key]
  end,
})

return M
