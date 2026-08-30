# Loom — a Vim-native agent system

Read `ARCHITECTURE.md` first. This is the file manifest.

```
ARCHITECTURE.md            the design and the reasoning behind it
AGENTS.md                  repo facts every agent reads (edit for your project)

bin/aw                     the dispatcher — worktrees, model routing, gate
bin/loom-session           tmux layout, works with plain vim

.agents/
  gate.sh                  fmt / check / clippy / test. The deterministic reviewer.
  zones.toml               hand / assist / auto. Enforced by pre-commit hook.
  PLAN_TEMPLATE.md
  TASK_TEMPLATE.md
  plans/   tasks/   decisions/   reviews/

.opencode/
  opencode.json            providers + per-role model assignment
  prompts/architect.md     designs, writes plans, never edits source
  prompts/scout.md         cheap read-only exploration (the big cost lever)
  prompts/implementer.md   one task, one worktree, must pass the gate
  prompts/reviewer.md      different provider than the implementer, on purpose
  prompts/build.md         direct hands-on agent for supervised work

nvim/loom.lua              optional Neovim layer. Delete it and nothing breaks.
```

## Install

```sh
cp -r .agents .opencode AGENTS.md /path/to/audat/
cp bin/aw bin/loom-session ~/.local/bin/
cp nvim/loom.lua ~/.config/nvim/lua/          # optional

cd /path/to/audat
aw install-hooks
$EDITOR .agents/zones.toml                    # do this honestly, it is the point

export ANTHROPIC_API_KEY=... ZAI_API_KEY=... DEEPSEEK_API_KEY=... MOONSHOT_API_KEY=...
opencode models                               # verify the IDs in opencode.json
```

For Neovim, add `require("loom").setup()` to your config.

## The loop

```sh
aw plan "streaming resampler"   # premium model, writes .agents/plans/0007-*.md
                                # you review the plan in vim, edit it, commit it
aw run 0007-c                   # cheap model, isolated worktree, gate-enforced
aw check 0007-c                 # different cheap model reviews the diff
aw diff 0007-c                  # you read it
aw land 0007-c                  # merge, clean up, tick the checkbox
```

Tasks marked `HAND` in the plan you write yourself. That is deliberate.

When you hit a rate limit: `export LOOM_TIER=lean` and keep going.
