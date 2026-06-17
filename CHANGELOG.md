# Changelog

## Unreleased

- Add support for project setup and run scripts.
- Add binding for opening an editor popup.
- Add binding for opening a shell popup.
- Add confirmation to worktree deletion.
- Resolve scripts from the main repository as a fallback.
- Centralize new worktrees under `$GROVE_ROOT/worktrees`.
- Fix unstaged preview for newly added files.
- Fix the switcher when the current project lives outside `$GROVE_ROOT`.

## v0.5.0 - April 22nd, 2026

- Add `GROVE_PREFIX` environment variable to configure the worktree prefix.
- Continue the prior agent session when opening an existing worktree.
- Remove the `grove review` command.
- Scope the switcher to the current project when invoked inside one.
- Strip `GROVE_PREFIX` from worktree names shown in the switcher.
- Fix file watcher preview to show only relevant changes for each section.

## v0.4.0 - April 6th, 2026

- Add `grove rename` to rename worktrees.
- Start new worktrees from the default branch.
- Hide stale worktree entries in the switcher.
- Fix the add and remove statistics for renamed files.
- Fix deletion of invalid worktree paths in the switcher.
- Fix file watcher preview opening in the wrong worktree.
- Fix file watcher actions to properly escape filenames with spaces.
- Fix file watcher to show individual files in untracked directories.
- Improve how filenames are provided to git commands.
- Improve worktree path matching to use fixed strings.

## v0.3.0 - February 28th, 2026

- Add worktree deletion with confirmation to the switcher.
- Add keyboard shortcut footer to file watcher and switcher.
- Fix preview for newly staged files.
- Fix preview for newly added files that have been modified or deleted.
- Group changes by status in the file watcher.
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
