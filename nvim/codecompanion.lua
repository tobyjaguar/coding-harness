-- codecompanion.lua — the editor layer.
--
-- Division of labour with opencode:
--
--   opencode        headless orchestration. aw plan / aw run / aw check.
--                   Worktrees, subagents, gate loops. No editor required.
--
--   CodeCompanion   human-in-the-loop. Inline edits, chat about the buffer,
--                   and the primary tool inside HAND zones where `aw` is
--                   off-limits by policy.
--
-- They compose: CodeCompanion has a built-in ACP adapter for opencode, so the
-- chat interaction can be backed by the same agent config the CLI uses.
--
-- CAVEAT: CodeCompanion's config keys have moved (`strategies` → `interactions`
-- in recent versions) and ACP adapters are chat-only. Check `:h codecompanion`
-- against your installed version before trusting the key names below.

return {
  "olimorris/codecompanion.nvim",
  dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
  opts = {
    adapters = {
      -- HTTP adapters: used by Inline and Cmd. Deliberately cheap — these are
      -- your highest-frequency, lowest-stakes interactions, and routing them
      -- here keeps them off the Anthropic quota entirely.
      http = {
        deepseek = function()
          return require("codecompanion.adapters").extend("deepseek", {
            env = { api_key = "DEEPSEEK_API_KEY" },
            schema = { model = { default = "deepseek-chat" } },
          })
        end,

        glm = function()
          return require("codecompanion.adapters").extend("openai_compatible", {
            env = {
              url = "https://api.z.ai/api/paas/v4",
              api_key = "ZAI_API_KEY",
            },
            schema = { model = { default = "glm-4.6" } },
          })
        end,

        -- Reserved for the rare case where you genuinely want the big model in
        -- the editor. Not a default anywhere, on purpose.
        fable = function()
          return require("codecompanion.adapters").extend("anthropic", {
            env = { api_key = "ANTHROPIC_API_KEY" },
            schema = { model = { default = "claude-fable-5" } },
          })
        end,
      },
    },

    interactions = {
      -- Chat is backed by opencode over ACP, so it inherits the same agent
      -- definitions, permissions and MCP config as the CLI. One source of truth.
      chat = {
        adapter = { name = "opencode" },
      },
      -- Inline writes into your buffer. This is the one place an agent touches
      -- your working tree, and it is acceptable because it is human-initiated,
      -- selection-scoped, and undone with `u`.
      inline = { adapter = "deepseek" },
      cmd    = { adapter = "deepseek" },
    },

    prompt_library = {
      -- Tutor mode. The hand-zone workflow: you get the spec and the failing
      -- test, you write the implementation.
      ["Tutor: contract only"] = {
        strategy = "chat",
        description = "Spec + failing test for hand-zone code. No implementation.",
        opts = { short_name = "tutor", is_slash_cmd = true },
        prompts = {
          {
            role = "system",
            content = [[
The user is learning Rust and this file is in a HAND zone. You must NOT write
the implementation. Produce only:

  1. a doc comment stating the contract, invariants, and edge cases
  2. the type signature, with a `todo!()` body
  3. a failing test that pins the behaviour, including boundary cases

For DSP code, be explicit about units, sample-rate assumptions, and what
happens at the first and last frame. Those are the things the compiler cannot
catch and the reason this code is hand-written.

If asked for the implementation, decline and explain the invariant instead.
]],
          },
          { role = "user", content = function(ctx)
              return "File: " .. ctx.filename .. "\n\n" .. require("codecompanion.helpers.actions").get_code(ctx.start_line, ctx.end_line)
            end,
          },
        },
      },

      ["Explain this borrow error"] = {
        strategy = "chat",
        description = "Walk through a lifetime/ownership error without fixing it",
        opts = { short_name = "borrow", is_slash_cmd = true },
        prompts = {
          {
            role = "system",
            content = [[
Explain the ownership or lifetime problem in the pasted code and compiler
output. Explain WHY the borrow checker is objecting in terms of the underlying
model. Describe the shape of a fix in prose. Do not write the corrected code —
the user is learning and needs to write it themselves.
]],
          },
        },
      },
    },
  },

  config = function(_, opts)
    require("codecompanion").setup(opts)

    local map = vim.keymap.set

    map({ "n", "v" }, "<leader>cc", "<cmd>CodeCompanionChat Toggle<cr>", { desc = "cc: chat" })
    map("v",          "<leader>ci", ":CodeCompanion<cr>",                { desc = "cc: inline edit" })
    map("n",          "<leader>ca", "<cmd>CodeCompanionActions<cr>",     { desc = "cc: actions" })
    map("v",          "<leader>ct", ":CodeCompanion /tutor<cr>",         { desc = "cc: tutor mode" })
    map("v",          "<leader>cb", ":CodeCompanion /borrow<cr>",        { desc = "cc: explain borrow error" })

    -- Zone guard. In a HAND zone, `aw run` is the wrong tool and the pre-commit
    -- hook will reject it anyway. Fail fast in the editor instead, and point at
    -- tutor mode. This is the boundary made visible rather than merely enforced.
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function(args)
        local name = vim.api.nvim_buf_get_name(args.buf)
        if name == "" or vim.bo[args.buf].buftype ~= "" then return end
        vim.fn.jobstart({ "aw", "zone", name }, {
          stdout_buffered = true,
          on_stdout = function(_, data)
            local line = data and data[1] or ""
            if line:match("→%s*hand") then
              vim.b[args.buf].loom_zone = "hand"
            end
          end,
        })
      end,
    })

    vim.api.nvim_create_user_command("Tutor", function()
      if vim.b.loom_zone ~= "hand" then
        vim.notify("not a hand zone — `aw run` is fine here", vim.log.levels.INFO)
      end
      vim.cmd("CodeCompanionChat /tutor")
    end, {})
  end,
}
