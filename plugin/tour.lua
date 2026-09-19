if vim.g.loaded_tour then
  return
end
vim.g.loaded_tour = true
require("tour.commands").setup()
