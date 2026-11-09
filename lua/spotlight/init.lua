local M = {}
local active_term = nil

local function open_my_explorer(start_path)
    local target_path = start_path and vim.fn.expand(start_path) or vim.fn.getcwd()

    if vim.fn.filereadable(target_path) == 1 then
        vim.cmd("edit " .. vim.fn.fnameescape(target_path))
        return
    end

    if vim.fn.isdirectory(target_path) == 0 then
        vim.notify("Path does not exist: " .. target_path, vim.log.levels.ERROR)
        return
    end

    local cwd = target_path
    vim.cmd("silent! cd " .. vim.fn.fnameescape(cwd))
    local raw_items = vim.fn.readdir(cwd)

    local dirs = {}
    local files = {}

    for _, item in ipairs(raw_items) do
        local full_path = cwd .. "/" .. item
        if vim.fn.isdirectory(full_path) == 1 then
            table.insert(dirs, item .. "/")
        else
            table.insert(files, item)
        end
    end

    table.sort(dirs)
    table.sort(files)

    local items = { "../" }
    for _, d in ipairs(dirs) do table.insert(items, d) end
    for _, f in ipairs(files) do table.insert(items, f) end

    vim.cmd("enew")
    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()

    vim.wo[win].winbar = "%=%#Directory# CWD: " .. cwd .. " "

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function()
            pcall(function() vim.wo[win].winbar = nil end)
        end
    })

    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.swapfile = false
    vim.bo.modifiable = true

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, items)
    vim.bo.modifiable = false

    vim.bo.filetype = "my_explorer"
    vim.cmd([[
        syntax clear
        syntax match ExplorerDir "^.*/$"
        syntax match ExplorerParent "^../$"
        syntax match ExplorerC ".*\.\(c\|cpp\|h\)$"
        syntax match ExplorerRust ".*\.rs$"
        syntax match ExplorerLua ".*\.lua$"
        syntax match ExplorerToml ".*\.toml$"
        
        highlight default link ExplorerDir Directory
        highlight default link ExplorerParent Comment
        highlight default link ExplorerC Function
        highlight default link ExplorerRust String
        highlight default link ExplorerLua Keyword
        highlight default link ExplorerToml Type
    ]])

    vim.keymap.set("n", "<CR>", function()
        local selected = vim.fn.getline('.')
        local target = selected:gsub("/$", "")

        local dest_path = cwd .. "/" .. target
        if vim.fn.isdirectory(dest_path) == 1 or target == ".." then
            vim.cmd("silent! cd " .. vim.fn.fnameescape(dest_path))
            open_my_explorer(vim.fn.getcwd())
        else
            vim.cmd("edit " .. vim.fn.fnameescape(dest_path))
        end
    end, { buffer = buf, desc = "Open file or folder" })

    vim.keymap.set("n", "<leader>e", function()
        vim.cmd("silent! cd ..")
        open_my_explorer(vim.fn.getcwd())
    end, { buffer = buf, desc = "Go up a directory" })

    -- 1. Create a new file or directory
    vim.keymap.set("n", "a", function()
        vim.ui.input({ prompt = "Create (end with '/' for folder): " }, function(name)
            if not name or name == "" then return end
            local new_path = cwd .. "/" .. name
            if name:match("/$") then
                vim.fn.mkdir(new_path, "p")
            else
                local new_dir = vim.fn.fnamemodify(new_path, ":h")
                if vim.fn.isdirectory(new_dir) == 0 then
                    vim.fn.mkdir(new_dir, "p")
                end
                local file = io.open(new_path, "w")
                if file then file:close() end
            end
            open_my_explorer(cwd)
        end)
    end, { buffer = buf, desc = "Add file/folder" })

    -- 2. Rename or Move
    vim.keymap.set("n", "r", function()
        local selected = vim.fn.getline('.')
        if selected == "../" then return end

        local target = selected:gsub("/$", "")
        local old_path = cwd .. "/" .. target

        vim.ui.input({ prompt = "Rename/Move to: ", default = target }, function(new_name)
            if new_name and new_name ~= "" and new_name ~= target then
                local new_path = cwd .. "/" .. new_name
                local new_dir = vim.fn.fnamemodify(new_path, ":h")
                if vim.fn.isdirectory(new_dir) == 0 then
                    vim.fn.mkdir(new_dir, "p")
                end
                vim.fn.rename(old_path, new_path)
                open_my_explorer(cwd)
            end
        end)
    end, { buffer = buf, desc = "Rename or Move" })

    -- 3. Delete
    vim.keymap.set("n", "dd", function()
        local selected = vim.fn.getline('.')
        if selected == "../" then return end

        local target = selected:gsub("/$", "")
        local target_path = cwd .. "/" .. target

        local choice = vim.fn.confirm("Delete '" .. target .. "'?", "&Yes\n&No", 2)
        if choice == 1 then
            vim.fn.delete(target_path, "rf")
            open_my_explorer(cwd)
        end
    end, { buffer = buf, desc = "Delete" })
end


-- =========================================================================
-- 2. SPOTLIGHT RUNNER
-- =========================================================================
local function spotlight_runner(initial_text)
    local buf = vim.api.nvim_create_buf(false, true)

    local width = math.floor(vim.o.columns * 0.5)
    if width < 50 then width = 50 end
    local height = 1
    local row = math.floor((vim.o.lines - height) / 2) - 2
    local col = math.floor((vim.o.columns - width) / 2)

    local opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Run in: " .. vim.fn.getcwd() .. " ",
        title_pos = "center"
    }

    local win = vim.api.nvim_open_win(buf, true, opts)

    -- Sanitize initial text and enter insert mode
    local clean_initial_text = vim.trim(initial_text or "")
    if type(clean_initial_text) == "string" and clean_initial_text ~= "" then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { clean_initial_text })
        vim.cmd("startinsert!")
    else
        vim.cmd("startinsert")
    end

    vim.keymap.set({ "n", "i" }, "<CR>", function()
        local raw_cmd = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
        local cmd = vim.trim(raw_cmd or "")
        vim.cmd("stopinsert")

        if cmd and cmd ~= "" then
            local expanded_cmd = vim.fn.expand(cmd)

            -- 1a. If it's a readable file, open it normally
            if vim.fn.filereadable(expanded_cmd) == 1 then
                vim.api.nvim_win_close(win, true)
                vim.cmd("edit " .. vim.fn.fnameescape(expanded_cmd))

            -- 1b. If it is a directory, route it to the custom file browser above
            elseif vim.fn.isdirectory(expanded_cmd) == 1 then
                vim.api.nvim_win_close(win, true)
                -- Passing the unescaped path so the explorer can process it cleanly
                open_my_explorer(expanded_cmd)

            else
                -- 2. It doesn't exist. Check if we should create a directory or file.
                local parent_dir = vim.fn.fnamemodify(expanded_cmd, ":h")
                local is_explicit_dir = cmd:match("[/\\]$")
                local has_path_separator = cmd:match("[/\\]")

                if has_path_separator and vim.fn.isdirectory(parent_dir) == 1 then
                    vim.api.nvim_win_close(win, true)

                    if is_explicit_dir then
                        vim.fn.mkdir(expanded_cmd, "p")
                    end
                    vim.cmd("edit " .. vim.fn.fnameescape(expanded_cmd))
                else
                    -- 3. Not a valid path or creation intent, run it in ToggleTerm
                    vim.api.nvim_win_close(win, true)

                    local Terminal = require("toggleterm.terminal").Terminal
                    local shell = vim.env.SHELL or "bash"

                    active_term = Terminal:new({
                        cmd = shell .. " -c '" .. cmd .. "; exec " .. shell .. "'",
                        direction = "float",
                        hidden = true,
                        close_on_exit = false,
                        float_opts = {
                            border = "rounded",
                            title_pos = "center",
                        },
                        on_open = function(t)
                            vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { buffer = t.bufnr })
                            vim.keymap.set("n", "q", function() t:close() end, { buffer = t.bufnr })
                            vim.schedule(function() vim.cmd("startinsert") end)
                        end,
                    })

                    active_term:toggle()
                end
            end
        else
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<Esc>", function()
        vim.cmd("stopinsert")
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf })

    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
end


-- =========================================================================
-- 3. WINDOW TOGGLE HELPER
-- =========================================================================
local function toggle_window_float()
    local win = vim.api.nvim_get_current_win()
    local config = vim.api.nvim_win_get_config(win)

    if config.relative ~= "" then
        vim.api.nvim_win_set_config(win, { relative = "" })
    else
        local width = math.floor(vim.o.columns * 0.8)
        local height = math.floor(vim.o.lines * 0.8)
        local row = math.floor((vim.o.lines - height) / 2)
        local col = math.floor((vim.o.columns - width) / 2)

        vim.api.nvim_win_set_config(win, {
            relative = "editor",
            width = width,
            height = height,
            row = row,
            col = col,
            border = "rounded",
        })
    end
end


-- =========================================================================
-- 4. SETUP AND REGISTRATION
-- =========================================================================
function M.setup(opts)
    -- Command to open spotlight with an optional path and autocomplete
    vim.api.nvim_create_user_command("Fb", function(cmd_opts)
        spotlight_runner(cmd_opts.args)
    end, { nargs = "?", complete = "file", desc = "Open Spotlight Runner" })

    -- Base Keymaps
    vim.keymap.set("n", "<leader>e", function() open_my_explorer() end, { desc = "Open Custom Filebrowser" })
    vim.keymap.set("n", "<leader>.", function() spotlight_runner() end, { desc = "Spotlight Runner" })
    vim.keymap.set("n", "<leader>fw", toggle_window_float, { desc = "Float Window" })

    -- Persistent Terminal Toggles via ToggleTerm Lua API
    vim.keymap.set("n", "<leader>t", function()
        if not active_term then
            local Terminal = require("toggleterm.terminal").Terminal
            active_term = Terminal:new({
                direction = "horizontal",
                hidden = true,
                close_on_exit = false,
            })
        end

        if active_term:is_open() then
            active_term:close()
            if active_term.direction == "float" then
                active_term.direction = "horizontal"
                active_term.size = 15
            else
                active_term.direction = "float"
            end
            active_term:open()
        else
            active_term:toggle()
        end
    end, { desc = "Toggle and Dock Active Terminal" })
end

return M
