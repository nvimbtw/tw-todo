vim.api.nvim_create_user_command("TwTodo", function()
    require("tw-todo.comment").insert("TODO")
end, { desc = "tw-todo: insert TODO comment" })

vim.api.nvim_create_user_command("TwFix", function()
    require("tw-todo.comment").insert("FIX")
end, { desc = "tw-todo: insert FIX comment" })

vim.api.nvim_create_user_command("TwList", function()
    require("tw-todo.picker").open()
end, { desc = "tw-todo: pick a pending task and jump to its comment" })

vim.api.nvim_create_user_command("TwHover", function()
    require("tw-todo.hover").show()
end, { desc = "tw-todo: show task details for the comment under the cursor" })

vim.api.nvim_create_user_command("TwDevelop", function()
    require("tw-todo.github").develop_at_cursor()
end, { desc = "tw-todo: create + checkout the develop branch for the comment's issue" })

vim.api.nvim_create_user_command("TwMerge", function()
    require("tw-todo.git").merge_picker()
end, { desc = "tw-todo: merge a finished develop branch back into its base" })

vim.api.nvim_create_user_command("TwSync", function()
    require("tw-todo.sync").sync_project()
end, { desc = "tw-todo: sync all comments in the project with taskwarrior" })
