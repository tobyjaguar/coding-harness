# Loom — a Vim-native agent system

Read `ARCHITECTURE.md` for the design and reasoning. This is the manifest and
quickstart.

## Billing policy (the point of all this)

Two flat subscriptions do the work; pay-per-token APIs are only a relief valve:

| Surface | Billing | Used for |
|---|---|---|
| Claude subscription (`claude` CLI) | flat | architect (+ reviewer at `deep` tier) |
| GLM Coding Plan (Z.ai, `ZHIPU_API_KEY`) | flat | scout, implementer — the ~85% token share |
| DeepSeek / Moonshot API keys | per-token, cheap | fallback when a sub window is exhausted; decorrelated review |

There is **no `ANTHROPIC_API_KEY` anywhere in this system**, by design. When
the Claude sub is rate-limited, the architect degrades to GLM instead of
falling through to an expensive API bill. `aw` detects rate-limit failures and
walks each role's fallback chain automatically; `LOOM_SKIP="claude"` or
`eval "$(aw tier lean)"` forces the degradation manually.

## Files

```
ARCHITECTURE.md            the design and the reasoning behind it
AGENTS.md                  repo-facts template every agent reads (edit per repo)
install.sh                 copies all of this into a target repo

bin/aw                     the dispatcher — worktrees, model routing, gate, doctor
bin/loom-session           tmux layout, works with plain vim

.agents/
  gate.sh                  fmt / clippy / test. The deterministic reviewer.
  zones.toml               hand / assist / auto. Enforced by pre-commit hook.
  PLAN_TEMPLATE.md  TASK_TEMPLATE.md
  plans/  tasks/  decisions/  reviews/

.opencode/
  opencode.json            per-role model assignment (built-in providers only)
  prompts/                 architect / scout / implementer / reviewer / build

nvim/loom.lua              optional Neovim layer. Delete it and nothing breaks.
nvim/codecompanion.lua     optional editor-chat layer (Neovim only)
```

## Requirements

`git`, `bash`, `python3` ≥ 3.11 (for `tomllib`), `jq`, `curl`, plus
[`opencode`](https://opencode.ai) and the `claude` CLI (logged in to your
subscription). `tmux` optional (for `loom-session`). Everything is
GNU/BSD-portable — the same scripts run on macOS and Linux; `aw doctor`
verifies a new machine in one shot.

## New machine bootstrap (Linux or macOS)

From zero to verified, in order:

```sh
# 1. base tools — Debian/Ubuntu shown; use dnf/pacman/brew equivalents
sudo apt install -y git jq curl python3 tmux        # python3 must be >= 3.11

# 2. the two agent CLIs
curl -fsSL https://opencode.ai/install | bash        # or: npm i -g opencode-ai
curl -fsSL https://claude.ai/install.sh | bash       # or: npm i -g @anthropic-ai/claude-code
claude                                               # first run: log in to your
                                                     # Claude subscription (browser)

# 3. this repo + your target project
git clone git@github.com:tobyjaguar/coding-harness.git
cd coding-harness && ./install.sh /path/to/your/repo # creates ~/.config/loom/env
$EDITOR ~/.config/loom/env                           # paste ZHIPU_API_KEY etc.

# 4. verify everything — binaries, keys, hooks, live model IDs
cd /path/to/your/repo && aw doctor
```

`aw doctor` is the machine's acceptance test: if it reports 0 failures, the
whole system works here. `~/.local/bin` must be on PATH (most distros do this
when the directory exists; log out/in if not).

## Install

```sh
./install.sh /path/to/audat        # copies harness, links bin, installs hook

cd /path/to/audat
$EDITOR .agents/zones.toml         # do this honestly, it is the point
$EDITOR AGENTS.md                  # repo facts, keep under 100 lines

$EDITOR ~/.config/loom/env         # paste keys here: ZHIPU_API_KEY=... etc.
                                   # chmod 600; aw sources it automatically,
                                   # so keys never live in a repo or profile

aw doctor                          # verify binaries, keys, and MODEL IDS
```

`claude` must be logged in to your Anthropic subscription (it already is if
you use Claude Code). Nothing else touches Anthropic.

### Verifying model IDs

Model catalogs move weekly; never trust a config's IDs. Three checks, free to
authoritative:

1. `aw doctor` — checks every model in the routing chains and `opencode.json`
   against the public models.dev catalog, and (for providers whose key is set)
   against the provider's **live `/models` endpoint** — the ground truth of
   what your account can call.
2. `opencode models` — what your installed opencode accepts.
3. GLM Coding Plan note: it is a distinct opencode provider,
   `zai-coding-plan/...` (endpoint `api.z.ai/api/coding/paas/v4`), not `zai/...`
   (pay-per-token). Same `ZHIPU_API_KEY` env var.

## The loop

```sh
aw plan "streaming resampler"   # Claude sub, interactive; writes .agents/plans/0007-*.md
                                # you review the plan in vim, edit it, commit it
aw run 0007-c                   # GLM sub, isolated worktree, gate-enforced
aw check 0007-c                 # different provider reviews the diff
aw diff 0007-c                  # you read it
aw land 0007-c                  # gate again, merge, clean up, tick the checkbox
```

Tasks marked `HAND` in the plan you write yourself. That is deliberate —
`aw plan` produces tutor-mode specs (contract + failing test + `todo!()`) for
those, and the pre-commit hook enforces the boundary.

When you hit a rate limit anywhere: `eval "$(aw tier lean)"` and keep going.

## Editors

The harness is editor-agnostic on purpose: every durable artifact is a file,
every action is a CLI command. Use VS Code (rust-analyzer + the Claude Code
extension + `.vscode/tasks.json`, installed by `install.sh`: the gate is the
default build task, wired into the Problems panel) for daily work, and plain
vim on any machine for surgery. Nothing changes between them.

## Plain-vim tier 0

`loom-session` gives you vim + shell + gate panes in tmux. Inside vim:

```vim
:cfile! .agents/reviews/0007-c-gate.log    " gate output into quickfix
set efm+=%*[\ ]-->\ %f:%l:%c               " rustc's arrow lines in quickfix
:e .agents/plans/0007-streaming-resampler.md   " gf on any path jumps to source
:r !aw scout "where is decode_flac called"     " scout answer into the buffer
```

Review diffs with `aw diff 0007-c` (read-only, filetype=diff) or fugitive's
`:Gdiffsplit` against the `agent/0007-c` branch.
