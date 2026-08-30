-- loom.lua — Neovim layer for the agent system.
--
-- Deliberately thin. Everything here also works from the shell; this is
-- convenience, not dependency. If you delete this file the system still works.
--
-- Install: put in ~/.config/nvim/lua/loom.lua, then `require("loom").setup()`

local M = {}

local function root()
  local r = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  return (vim.v.shell_error == 0) and r or vim.fn.getcwd()
end

local function aw(args, on_done)
  local cmd = "aw " .. args
  vim.notify("loom: " .. cmd, vim.log.levels.INFO)
  vim.fn.jobstart(cmd, {
    cwd = root(),
    stdout_buffered = true,
    on_stdout = function(_, data) if on_done then on_done(data) end end,
    on_exit = function(_, code)
      vim.notify("loom: " .. cmd .. " exited " .. code,
        code == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
    end,
  })
end

-- Run the gate, results into the quickfix list. This is the one you will use
-- most. `]q` / `[q` to walk errors.
function M.gate()
  vim.cmd("cclose")
  local lines = {}
  vim.fn.jobstart({ "./.agents/gate.sh" }, {
    cwd = root(),
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, d) vim.list_extend(lines, d or {}) end,
    on_stderr = function(_, d) vim.list_extend(lines, d or {}) end,
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("gate: green", vim.log.levels.INFO)
      else
        vim.fn.setqflist({}, " ", { title = "gate", lines = lines,
          efm = "%f:%l:%c: %m,%f:%l: %m" })
        vim.cmd("copen")
      end
    end,
  })
end

-- Open the most recently modified plan.
function M.plan()
  local dir = root() .. "/.agents/plans"
  local files = vim.fn.glob(dir .. "/*.md", false, true)
  if #files == 0 then return vim.notify("no plans yet", vim.log.levels.WARN) end
  table.sort(files, function(a, b)
    return vim.fn.getftime(a) > vim.fn.getftime(b)
  end)
  vim.cmd("edit " .. vim.fn.fnameescape(files[1]))
end

-- Pick a task from .agents/tasks and open it beside the plan.
function M.tasks()
  local files = vim.fn.glob(root() .. "/.agents/tasks/*.md", false, true)
  vim.ui.select(files, { prompt = "task:", format_item = vim.fn.fnamemodify },
    function(choice) if choice then vim.cmd("vsplit " .. vim.fn.fnameescape(choice)) end end)
end

-- Review an agent branch diff.
function M.review(task)
  task = task or vim.fn.input("task id: ")
  if task == "" then return end
  local ok = pcall(vim.cmd, "DiffviewOpen HEAD..agent/" .. task)
  if not ok then
    vim.cmd("tabnew | term git diff HEAD..agent/" .. task)
  end
end

-- Ask scout about the identifier under the cursor. Answer lands in a scratch
-- split, so it is a normal buffer you can yank from.
function M.scout(q)
  q = q or ("where is " .. vim.fn.expand("<cword>") .. " defined and what calls it")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "scout: " .. q, "", "..." })
  vim.cmd("vsplit"); vim.api.nvim_win_set_buf(0, buf)
  vim.bo[buf].filetype = "markdown"
  vim.fn.jobstart({ "aw", "scout", q }, {
    cwd = root(),
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.api.nvim_buf_set_lines(buf, 2, -1, false, data)
      end
    end,
  })
end

-- Which zone is the current file in? Check before you let an agent near it.
function M.zone()
  local f = vim.fn.expand("%:p")
  if f == "" then return end
  aw("zone " .. vim.fn.shellescape(f), function(data)
    if data and data[1] then vim.notify(data[1], vim.log.levels.INFO) end
  end)
end

-- Send the current visual selection to the build agent as context.
function M.send_selection()
  local s = vim.fn.getpos("'<")[2]
  local e = vim.fn.getpos("'>")[2]
  local file = vim.fn.expand("%:.")
  local q = vim.fn.input("prompt: ")
  if q == "" then return end
  local ctx = string.format("Regarding %s lines %d-%d: %s", file, s, e, q)
  vim.cmd("tabnew | term opencode run --agent build " .. vim.fn.shellescape(ctx))
end

function M.setup(opts)
  opts = opts or {}
  local prefix = opts.prefix or "<leader>a"
  local map = function(k, fn, desc)
    vim.keymap.set("n", prefix .. k, fn, { desc = "loom: " .. desc })
  end

  map("g", M.gate,   "run gate → quickfix")
  map("p", M.plan,   "open latest plan")
  map("t", M.tasks,  "pick a task")
  map("r", M.review, "review agent diff")
  map("s", M.scout,  "ask scout about <cword>")
  map("z", M.zone,   "zone of current file")

  vim.keymap.set("v", prefix .. "b", M.send_selection,
    { desc = "loom: send selection to build agent" })

  vim.api.nvim_create_user_command("Gate",  M.gate,  {})
  vim.api.nvim_create_user_command("Plan",  M.plan,  {})
  vim.api.nvim_create_user_command("Scout", function(a) M.scout(a.args) end, { nargs = "*" })
  vim.api.nvim_create_user_command("Review", function(a) M.review(a.args) end, { nargs = "?" })

  -- Plan files: make task ids and paths jumpable with gf.
  vim.api.nvim_create_autocmd("BufRead", {
    pattern = { "*/.agents/plans/*.md", "*/.agents/tasks/*.md" },
    callback = function()
      vim.opt_local.path:append(root())
      vim.opt_local.isfname:append("-")
      vim.opt_local.conceallevel = 0
    end,
  })
end

return M
