if vim.g.loaded_impostor_pkg then
  return
end
vim.g.loaded_impostor_pkg = true

vim.api.nvim_create_user_command("ImpostorCheck", function()
  require("impostor-pkg").check({ force = true })
end, {
  desc = "Scan the current project's npm/yarn/pnpm dependencies for malicious or risky packages",
})

vim.api.nvim_create_user_command("Impostor", function()
  require("impostor-pkg").check({ force = true })
end, {
  desc = "Alias for :ImpostorCheck",
})

vim.api.nvim_create_user_command("ImpostorInstall", function()
  require("impostor-pkg").install()
end, {
  desc = "Scan new package.json dependencies and install them with the project's package manager",
})
