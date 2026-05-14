local util = require("config.util")

local M = {}

local git_sign_group = "git_changed_lines"
local git_deleted_namespace = vim.api.nvim_create_namespace("git_deleted_lines")
local refresh_netrw_git_status = function() end

local show_deleted_lines = false

local function place_deleted_line_marker(buffer, new_start, new_count)
  local line_count = vim.api.nvim_buf_line_count(buffer)
  local mark_line
  local above_line

  if new_count == 0 then
    mark_line = math.max(math.min(new_start, line_count), 0)
    above_line = true
  else
    mark_line = math.max(math.min(new_start + new_count - 2, line_count - 1), 0)
    above_line = false
  end

  vim.api.nvim_buf_set_extmark(buffer, git_deleted_namespace, mark_line, 0, {
    virt_lines = {
      { { "  " .. string.rep("─", 24), "GitDeletedLine" } },
    },
    virt_lines_above = above_line,
  })
end

function M.mark_changed_lines(buffer)
  local file_path = vim.api.nvim_buf_get_name(buffer)

  vim.fn.sign_unplace(git_sign_group, { buffer = buffer })
  vim.api.nvim_buf_clear_namespace(buffer, git_deleted_namespace, 0, -1)

  if file_path == "" then
    return
  end

  local root = util.git_root_for(vim.fs.dirname(file_path))

  if not root then
    return
  end

  local diff = util.git_output(root, { "diff", "--unified=0", "--no-ext-diff", "--", util.relative_path(root, file_path) })

  if not diff then
    return
  end

  local sign_id = 1

  for _, line in ipairs(diff) do
    local old_start, old_count, new_start, new_count =
      line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

    if old_start then
      old_count = tonumber(old_count ~= "" and old_count or "1")
      new_start = tonumber(new_start)
      new_count = tonumber(new_count ~= "" and new_count or "1")

      if show_deleted_lines and old_count > new_count then
        place_deleted_line_marker(buffer, new_start, new_count)
      end

      if new_count > 0 then
        local changed_count = math.min(old_count, new_count)

        for offset = 0, changed_count - 1 do
          vim.fn.sign_place(sign_id, git_sign_group, "GitModifiedLine", buffer, {
            lnum = new_start + offset,
            priority = 10,
          })
          sign_id = sign_id + 1
        end

        for offset = changed_count, new_count - 1 do
          vim.fn.sign_place(sign_id, git_sign_group, "GitAddedLine", buffer, {
            lnum = new_start + offset,
            priority = 10,
          })
          sign_id = sign_id + 1
        end
      end
    end
  end
end

function M.add_file(file_path, options)
  options = options or {}

  if file_path == "" or (not options.allow_missing and vim.fn.filereadable(file_path) ~= 1) then
    vim.notify("Current buffer is not a file", vim.log.levels.WARN)
    return
  end

  local root = options.root or util.git_root_for(vim.fs.dirname(file_path))

  if not root then
    vim.notify("Current file is not inside a git repo", vim.log.levels.WARN)
    return
  end

  local relative_file = util.relative_path(root, file_path)
  local output = util.git_output(root, { "add", "--", relative_file })

  if not output then
    vim.notify("git add failed: " .. relative_file, vim.log.levels.ERROR)
    return
  end

  M.mark_changed_lines(vim.api.nvim_get_current_buf())
  refresh_netrw_git_status()
  vim.notify("git add: " .. relative_file, vim.log.levels.INFO)
end

function M.add_current_file()
  M.add_file(vim.api.nvim_buf_get_name(0))
end

function M.setup(refresh_netrw)
  refresh_netrw_git_status = refresh_netrw or refresh_netrw_git_status

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained" }, {
    callback = function(event)
      M.mark_changed_lines(event.buf)
      refresh_netrw_git_status()
    end,
  })
end

return M
