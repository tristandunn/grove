# grove

An agent worktree manager built on tmux.

One tmux session per project, one window per worktree, with a fixed 3-pane
layout that includes the agent on the left, a file watcher on the top-right, and
a terminal on the bottom-right.

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
bind -T grove b display-popup -w 50% -h 3 -E -d "#{pane_current_path}" 'printf "New Name: " && read -r name && grove rename "$name"'
bind -T grove d run-shell "grove rm"
bind -T grove g display-popup -w 60% -h 50% -E "grove switch"
bind -T grove n display-popup -w 50% -h 3 -E -d "#{pane_current_path}" 'printf "Task Name: " && read -r name && grove new "$name"'
bind -T grove r run-shell "grove run"
```

- `prefix + g a` — Add another agent pane to the current worktree.
- `prefix + g b` — Rename the current worktree and its branch.
- `prefix + g d` — Delete and close the current worktree.
- `prefix + g g` — Open the worktree switcher.
- `prefix + g n` — Prompt for a task name and create a new worktree.
- `prefix + g r` — Execute the project run script in the shell pane.

## Usage

### New Worktree

Create a new worktree from inside any repository:

```sh
grove new fix login bug
```

This creates a worktree at `../worktrees/grove/fix-login-bug`, a branch
`grove/fix-login-bug`, and opens a tmux window with the full layout.

#### Custom Agent

The left pane runs `claude` by default, which you can override with
`GROVE_AGENT`:

```sh
GROVE_AGENT="codex" grove new refactor auth
```

### Rename Worktree

Rename a worktree from inside any worktree directory:

```sh
grove rename new task name
```

This renames the branch, moves the worktree directory, and updates the tmux
window name.

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

### Project Scripts

Grove supports two optional scripts in the `.grove/` directory at the root of
your repository:

- **`.grove/setup.sh`** — Runs automatically in the shell pane when a new
  worktree is created with `grove new`. Use this for installing dependencies,
  starting dev servers, or any other setup tasks.
- **`.grove/run.sh`** — Runs on demand via `grove run`. Use this for recurring
  tasks like restarting a dev server or running a build.

Both scripts must be executable. If `setup.sh` exists but is not executable,
grove shows a transient warning instead of running it.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `GROVE_AGENT` | `claude` | Command to run in the left pane. |
| `GROVE_PREFIX` | `grove/` | Branch and directory prefix for new worktrees. |
| `GROVE_ROOT` | `~/Sites` | Parent directory to scan for repositories. |
| `GROVE_WORKTREES` | `<repository>/../worktrees` | Directory to create worktrees in. |

## License

Grove uses the MIT license. See [LICENSE](LICENSE) for more details.
