# grove

An agent worktree manager built on tmux.

One tmux session per project, one window per worktree, with a fixed 3-pane
layout that includes the agent on the left, a file watcher on the top-right, and
a terminal on the bottom-right. The left and bottom-right panes run nested tmux
sessions, so additional agents and terminals open as tabs instead of splits.

## Dependencies

- bash
- fzf
- git
- tmux

## Install

```sh
make install
```

This symlinks `bin/grove` into `~/.local/bin/`.

### tmux

Add optional shortcuts to your `~/.tmux.conf` configuration:

```sh
bind g switch-client -T grove
bind -T grove a run-shell "grove add-agent"
bind -T grove d run-shell "grove rm"
bind -T grove g display-popup -w 60% -h 50% -E "grove switch"
bind -T grove n display-popup -w 50% -h 3 -E -d "#{pane_current_path}" 'printf "task name: " && read -r name && grove new "$name"'
bind -T grove r run-shell "grove review"
```

- `prefix + g a` — Add another agent tab to the current worktree.
- `prefix + g d` — Delete and close the current worktree.
- `prefix + g g` — Open the worktree switcher.
- `prefix + g n` — Prompt for a task name and create a new worktree.
- `prefix + g r` — Open a review agent tab for the current changes.

You can also add this binding to forward your prefix to the nested tmux sessions:

```sh
bind a send-keys C-a
```

This lets you use `prefix + a` followed by any inner tmux key, such as `n` for
next tab or `p` for previous tab.

## Usage

### New Worktree

Create a new worktree from inside any repository:

```sh
grove new fix login bug
```

This creates a worktree at `../worktrees/fix-login-bug-a3f`, a branch
`grove/fix-login-bug-a3f`, and opens a tmux window with the full layout.

#### Custom Agent

The left pane runs `claude` by default, which you can override with
`GROVE_AGENT`:

```sh
GROVE_AGENT="codex" grove new refactor auth
```

### Remove Worktree

Delete a worktree from inside any worktree directory:

```sh
grove rm
```

This removes the worktree, deletes the local branch, and kills the window.

### Switch Worktrees

Switch to any other worktree within `GROVE_ROOT`:

```sh
grove switch
```

This switches to an existing tmux window if one is open, otherwise creates a new
window with the full layout.

### File Watcher

The top-right pane runs a file watcher that displays changed files with added and
removed line counts. It supports the following keybindings:

- `Enter` — View the full diff for the selected file in a popup.
- `Ctrl-a` — Stage the selected file.
- `Ctrl-u` — Unstage the selected file.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `GROVE_AGENT` | `claude` | Command to run in the left pane. |
| `GROVE_ROOT` | `~/Sites` | Parent directory to scan for repositories. |
| `GROVE_WORKTREES` | `<repository>/../worktrees` | Directory to create worktrees in. |

## License

Grove uses the MIT license. See [LICENSE](LICENSE) for more details.
