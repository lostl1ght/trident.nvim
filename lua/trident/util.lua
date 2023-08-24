local M = {}

---@param msg any
---@param level integer
function M.notify(msg, level)
  vim.notify(msg, level, { title = 'Trident' })
end

function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

function M.info(msg)
  M.notify(msg, vim.log.levels.INFO)
end

function M.debug(msg)
  M.notify(msg, vim.log.levels.DEBUG)
end

return M
