# Changelog

## Unreleased

- Add worktree deletion with confirmation to the switcher.
- Group worktrees by project with headers in the switcher.
- Display the current project first in the switcher.
- Hide project name in worktree switcher to improve search.
- Improve handling of session dimensions.

## v0.2.0 - February 26th, 2026

- Use slug instead of ID for tmux window names.
- Ensure spawning an agent starts in the worktree root.
- Display error messages in status bar when using tmux.
- Improve session name sanitization to also replace colons as separators.

## v0.1.0 - February 25th, 2026

- Add `grove new` to create a worktree workspace with a three-pane layout.
- Add `grove rm` to remove the current worktree, delete the branch, and close the window.
- Add `grove switch` to switch to any workspace across repositories under `GROVE_ROOT`.
- Add the ability to view full changes for a file in a popup from the file watcher with `Enter`.
- Add the ability to stage and unstage files from the file watcher with `Ctrl-a` and `Ctrl-u`.
- Display added and removed line counts in the file watcher.
- Add `GROVE_AGENT` environment variable to configure the agent command.
- Add `GROVE_ROOT` environment variable to configure the directory scanned for repositories.
- Add `GROVE_WORKTREES` environment variable to configure the worktree directory.
- Add `grove add-agent` to open an additional agent pane within the workspace.
- Add `grove review` to open an agent pane with an automatic review prompt.
