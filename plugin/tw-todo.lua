vim.api.nvim_create_user_command("TwTodo", function()
    require("tw-todo.comment").insert("TODO")
end, { desc = "tw-todo: insert TODO comment" })

vim.api.nvim_create_user_command("TwFix", function()
    require("tw-todo.comment").insert("FIX")
end, { desc = "tw-todo: insert FIX comment" })

vim.api.nvim_create_user_command("TwList", function()
    require("tw-todo.picker").open()
end, { desc = "tw-todo: pick a pending task and jump to its comment" })

vim.api.nvim_create_user_command("TwSync", function()
    require("tw-todo.sync").sync_project()
end, { desc = "tw-todo: sync all comments in the project with taskwarrior" })
