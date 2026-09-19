local M = {}
local function run(action, ...)
  local ok, err = pcall(require("tour")[action], ...)
  if not ok then
    vim.notify("tour.nvim: " .. err, vim.log.levels.ERROR)
  end
end

function M.setup()
  for suffix, action in pairs({
    Resume = "resume",
    Next = "next",
    Prev = "prev",
    Overview = "overview",
    Save = "save",
    Close = "close",
    Finish = "finish",
    Restart = "restart",
  }) do
    vim.api.nvim_create_user_command("Tour" .. suffix, function()
      run(action)
    end, { desc = "Tour: " .. action })
  end
  vim.api.nvim_create_user_command("TourGoto", function(args)
    run("goto_step", tonumber(args.args))
  end, {
    nargs = 1,
    complete = function()
      local data = require("tour").current()
      local result = {}
      for i = 1, data and #data.steps or 0 do
        result[i] = tostring(i)
      end
      return result
    end,
  })
  vim.api.nvim_create_user_command("TourLoad", function(args)
    run("load", args.args)
  end, { nargs = 1, complete = "file" })
  vim.api.nvim_create_user_command("TourOpen", function(args)
    if args.args == "" then
      require("tour").current()
      require("tour.session").library()
    else
      run("open", args.args)
    end
  end, {
    nargs = "?",
    complete = function()
      return vim.tbl_map(function(data)
        return data.id
      end, require("tour").list())
    end,
  })
  vim.api.nvim_create_user_command("TourList", function(args)
    require("tour").current()
    require("tour.session").library({ all = args.bang })
  end, { bang = true })
  for _, action in ipairs({
    "next",
    "prev",
    "overview",
    "resume",
    "close",
    "finish",
    "restart",
    "save",
  }) do
    vim.keymap.set("n", "<Plug>(tour-" .. action .. ")", function()
      run(action)
    end, { desc = "Tour " .. action })
  end
end

return M
