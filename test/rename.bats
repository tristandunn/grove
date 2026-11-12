#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  REPO=$(make_repo project)
  WORKTREE=$(make_worktree "${REPO}" "grove-old")
  cd "${WORKTREE}"
}

# --- Arguments ---------------------------------------------------------------

@test "rename: no arguments prints usage and exits 1" {
  run_grove rename

  assert_failure 1
  assert_output ""
  assert_stderr "Usage: grove rename <new-name>"
}

@test "rename: --path with no arguments prints usage and exits 1" {
  run_grove rename --path

  assert_failure 1
  assert_stderr "Usage: grove rename --path <worktree-path> <new-name>"
}

@test "rename: --path with only a path prints usage and exits 1" {
  run_grove rename --path "${WORKTREE}"

  assert_failure 1
  assert_stderr "Usage: grove rename --path <worktree-path> <new-name>"
  assert [ -d "${WORKTREE}" ]
}

@test "rename: outside a git repository errors" {
  cd "${TEST_TMP}"

  run_grove rename new-name

  assert_failure 1
  assert_stderr "Error: Not inside a git repository."
}

@test "rename: --path with a directory that is not a repository fails" {
  mkdir "${TEST_TMP}/plain"

  run_grove rename --path "${TEST_TMP}/plain" new-name

  assert_failure
  assert_stderr --partial "fatal"
}

@test "rename: --path with a missing directory fails" {
  run_grove rename --path "${TEST_TMP}/missing" new-name

  assert_failure
  assert_stderr --partial "fatal"
}

# --- Main worktree -----------------------------------------------------------

@test "rename: refuses the main worktree" {
  cd "${REPO}"

  run_grove rename new-name

  assert_failure 1
  assert_stderr "Error: Cannot rename the main worktree."
  assert branch_exists "${REPO}" "main"
}

@test "rename: --path refuses the main worktree" {
  run_grove rename --path "${REPO}" new-name

  assert_failure 1
  assert_stderr "Error: Cannot rename the main worktree."
  assert branch_exists "${REPO}" "main"
  refute branch_exists "${REPO}" "grove-new-name"
}

# --- Renaming ----------------------------------------------------------------

@test "rename: renames the branch and moves the directory keeping the prefix" {
  run_grove rename new name

  assert_success
  assert_output ""
  assert [ -d "${GROVE_WORKTREES}/grove-new-name" ]
  assert [ ! -e "${WORKTREE}" ]
  assert branch_exists "${REPO}" "grove-new-name"
  refute branch_exists "${REPO}" "grove-old"
  assert worktree_registered "${REPO}" "${GROVE_WORKTREES}/grove-new-name"
  assert_equal "$(git -C "${GROVE_WORKTREES}/grove-new-name" rev-parse --abbrev-ref HEAD)" "grove-new-name"
}

@test "rename: preserves the worktree's files and commits" {
  commit_file "${WORKTREE}" kept.txt "kept"
  printf 'dirty' > "${WORKTREE}/untracked.txt"
  local head
  head=$(git -C "${WORKTREE}" rev-parse HEAD)

  run_grove rename renamed

  assert_success
  assert_equal "$(git -C "${GROVE_WORKTREES}/grove-renamed" rev-parse HEAD)" "${head}"
  assert [ -f "${GROVE_WORKTREES}/grove-renamed/kept.txt" ]
  assert [ -f "${GROVE_WORKTREES}/grove-renamed/untracked.txt" ]
}

@test "rename: works from a subdirectory of the worktree" {
  mkdir -p "${WORKTREE}/sub/dir"
  cd "${WORKTREE}/sub/dir"

  run_grove rename deep

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-deep" ]
}

@test "rename: --path renames a worktree from the main repository" {
  cd "${REPO}"

  run_grove rename --path "${WORKTREE}" via path

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-via-path" ]
  assert branch_exists "${REPO}" "grove-via-path"
  refute branch_exists "${REPO}" "grove-old"
}

@test "rename: --path from outside any repository leaves branch and directory consistent" {
  skip "BUG: git worktree move runs without -C, so it fails outside a repository after git branch -m already renamed the branch, leaving the branch and directory out of sync."
  cd "${TEST_TMP}"

  run_grove rename --path "${WORKTREE}" via path

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-via-path" ]
  assert branch_exists "${REPO}" "grove-via-path"
}

@test "rename: a custom prefix is applied to the new name" {
  GROVE_PREFIX="task-" run_grove rename thing

  assert_success
  assert [ -d "${GROVE_WORKTREES}/task-thing" ]
  assert branch_exists "${REPO}" "task-thing"
}

@test "rename: an empty prefix gives an unprefixed name" {
  GROVE_PREFIX="" run_grove rename thing

  assert_success
  assert [ -d "${GROVE_WORKTREES}/thing" ]
  assert branch_exists "${REPO}" "thing"
}

@test "rename: does not strip an existing prefix from the new name" {
  run_grove rename grove-thing

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-grove-thing" ]
}

@test "rename: slugifies uppercase, punctuation and repeated hyphens" {
  run_grove rename "--Fix: Login/Auth!!  now--"

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-fix-loginauth-now" ]
}

@test "rename: slugifies non-ASCII characters away" {
  run_grove rename "Café Über"

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-caf-ber" ]
}

@test "rename: a name that produces an empty slug errors without changes" {
  run_grove rename "!!!"

  assert_failure 1
  assert_stderr "Error: New name produced an empty slug."
  assert [ -d "${WORKTREE}" ]
  assert branch_exists "${REPO}" "grove-old"
}

@test "rename: refuses to overwrite an existing worktree path" {
  mkdir -p "${GROVE_WORKTREES}/grove-taken"

  run_grove rename taken

  assert_failure 1
  assert_stderr "Error: Path already exists: ${GROVE_WORKTREES}/grove-taken"
  assert [ -d "${WORKTREE}" ]
}

@test "rename: leaves the branch unchanged when the target path exists" {
  mkdir -p "${GROVE_WORKTREES}/grove-taken"

  run_grove rename taken

  assert_failure 1
  assert branch_exists "${REPO}" "grove-old"
  refute branch_exists "${REPO}" "grove-taken"
  assert_equal "$(git -C "${WORKTREE}" rev-parse --abbrev-ref HEAD)" "grove-old"
}

@test "rename: renaming to the current name is refused as an existing path" {
  run_grove rename old

  assert_failure 1
  assert_stderr "Error: Path already exists: ${WORKTREE}"
  assert branch_exists "${REPO}" "grove-old"
}

@test "rename: an existing branch of the new name fails without moving anything" {
  git -C "${REPO}" branch grove-taken

  run_grove rename taken

  assert_failure
  assert_stderr --partial "grove-taken"
  assert [ -d "${WORKTREE}" ]
  assert [ ! -e "${GROVE_WORKTREES}/grove-taken" ]
  assert branch_exists "${REPO}" "grove-old"
}

@test "rename: a worktree whose directory name differs from its branch uses the parent directory" {
  local -r custom="${TEST_TMP}/elsewhere/custom-dir"
  mkdir -p "${TEST_TMP}/elsewhere"
  git -C "${REPO}" worktree add --quiet "${custom}" -b feature
  cd "${custom}"

  run_grove rename thing

  assert_success
  assert [ -d "${TEST_TMP}/elsewhere/grove-thing" ]
  assert [ ! -e "${custom}" ]
  assert branch_exists "${REPO}" "grove-thing"
  assert [ ! -e "${GROVE_WORKTREES}/grove-thing" ]
}

@test "rename: a branch containing a slash keeps the nested layout" {
  git -C "${REPO}" worktree add --quiet "${GROVE_WORKTREES}/feat/old" -b feat/old
  cd "${GROVE_WORKTREES}/feat/old"

  GROVE_PREFIX="feat/" run_grove rename thing

  assert_success
  assert [ -d "${GROVE_WORKTREES}/feat/thing" ]
  assert branch_exists "${REPO}" "feat/thing"
}

@test "rename: a detached worktree fails without moving anything" {
  git -C "${WORKTREE}" checkout --quiet --detach

  run_grove rename thing

  assert_failure
  assert [ -d "${WORKTREE}" ]
  assert [ ! -e "${GROVE_WORKTREES}/grove-thing" ]
}

# --- tmux --------------------------------------------------------------------

@test "rename: outside tmux makes no tmux calls" {
  run_grove rename thing

  assert_success
  refute_any_tmux_call
}

@test "rename: renames the tmux window whose pane is at the new path" {
  enter_tmux
  tmux_add_pane grove 2 0 0 1 %5 "${GROVE_WORKTREES}/grove-thing"

  run_grove rename thing

  assert_success
  assert_tmux_call_exact "rename-window -t grove:2 grove-thing"
}

@test "rename: matches a pane in a subdirectory of the new path" {
  enter_tmux
  tmux_add_pane grove 4 0 0 1 %5 "${GROVE_WORKTREES}/grove-thing/sub/dir"

  run_grove rename thing

  assert_success
  assert_tmux_call_exact "rename-window -t grove:4 grove-thing"
}

@test "rename: does not rename a window when no pane is at the new path" {
  enter_tmux
  tmux_add_pane grove 2 0 0 1 %5 "${TEST_TMP}"

  run_grove rename thing

  assert_success
  refute_tmux_called "rename-window"
}

@test "rename: does not rename windows whose path only shares a prefix" {
  enter_tmux
  tmux_add_pane grove 2 0 0 1 %5 "${GROVE_WORKTREES}/grove-thing-two"

  run_grove rename thing

  assert_success
  refute_tmux_called "rename-window"
}

@test "rename: renames only the first matching window" {
  enter_tmux
  tmux_add_pane grove 2 0 0 1 %5 "${GROVE_WORKTREES}/grove-thing"
  tmux_add_pane grove 3 0 0 1 %6 "${GROVE_WORKTREES}/grove-thing"

  run_grove rename thing

  assert_equal "$(tmux_call_count "rename-window")" "1"
  assert_tmux_call_exact "rename-window -t grove:2 grove-thing"
}

@test "rename: inside tmux, changes to the pane path before resolving the repository" {
  enter_tmux
  tmux_fixture pane_current_path "${WORKTREE}"
  cd "${TEST_TMP}"

  run_grove rename thing

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-thing" ]
  assert_tmux_called "display-message -p #{pane_current_path}"
}

@test "rename: inside tmux, a pane path outside any repository errors" {
  enter_tmux
  mkdir "${TEST_TMP}/plain"
  tmux_fixture pane_current_path "${TEST_TMP}/plain"

  run_grove rename thing

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: Not inside a git repository.'"
}

@test "rename: inside tmux, errors are shown with display-message" {
  enter_tmux
  cd "${REPO}"
  tmux_fixture pane_current_path "${REPO}"

  run_grove rename thing

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: Cannot rename the main worktree.'"
}

@test "rename: --path does not consult the tmux pane path" {
  enter_tmux
  cd "${REPO}"

  run_grove rename --path "${WORKTREE}" thing

  assert_success
  refute_tmux_called "display-message -p"
}
