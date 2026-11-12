#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  REPO=$(make_repo project)
  WORKTREE=$(make_worktree "${REPO}" "grove-task")
  cd "${WORKTREE}"
}

# --- --path validation -------------------------------------------------------

@test "rm: --path without an argument errors" {
  run_grove rm --path

  assert_failure 1
  assert_stderr "Error: grove rm --path requires a path argument."
  assert [ -d "${WORKTREE}" ]
}

@test "rm: --path with an empty argument errors" {
  run_grove rm --path ""

  assert_failure 1
  assert_stderr "Error: grove rm --path requires a path argument."
}

@test "rm: --path with a path that does not exist errors" {
  run_grove rm --path "${TEST_TMP}/nope"

  assert_failure 1
  assert_stderr "Error: Not a valid worktree: ${TEST_TMP}/nope"
}

@test "rm: --path with a plain directory errors" {
  mkdir "${TEST_TMP}/plain"

  run_grove rm --path "${TEST_TMP}/plain"

  assert_failure 1
  assert_stderr "Error: Not a valid worktree: ${TEST_TMP}/plain"
  assert [ -d "${TEST_TMP}/plain" ]
}

@test "rm: --path with a directory of another repository errors" {
  local other
  other=$(make_repo other)

  run_grove rm --path "${other}/../other/nope"

  assert_failure 1
  assert_stderr --partial "Not a valid worktree"
}

@test "rm: --path with a registered directory that is already gone removes the stale entry" {
  rm -rf "${WORKTREE}"
  cd "${REPO}"

  run_grove rm --path "${WORKTREE}"

  assert_success
  refute worktree_registered "${REPO}" "${WORKTREE}"
  refute branch_exists "${REPO}" "grove-task"
}

# --- Main worktree -----------------------------------------------------------

@test "rm: refuses the main worktree" {
  cd "${REPO}"

  run_grove rm

  assert_failure 1
  assert_stderr "Error: Cannot remove the main worktree. Run this from inside a task worktree."
  assert [ -d "${REPO}/.git" ]
  assert branch_exists "${REPO}" "main"
}

@test "rm: --path refuses the main worktree" {
  run_grove rm --path "${REPO}"

  assert_failure 1
  assert_stderr "Error: Cannot remove the main worktree. Run this from inside a task worktree."
  assert [ -d "${REPO}/.git" ]
}

@test "rm: refuses the main worktree from one of its subdirectories" {
  mkdir "${REPO}/sub"
  cd "${REPO}/sub"

  run_grove rm

  assert_failure 1
  assert_stderr "Error: Cannot remove the main worktree. Run this from inside a task worktree."
  assert [ -d "${REPO}/.git" ]
  assert branch_exists "${REPO}" "main"
}

@test "rm: outside a git repository errors" {
  cd "${TEST_TMP}"

  run_grove rm

  assert_failure 1
  assert_stderr "Error: Not inside a git repository."
}

# --- Removing ----------------------------------------------------------------

@test "rm: removes the current worktree and its branch" {
  run_grove rm

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
  assert [ ! -e "${WORKTREE}" ]
  refute worktree_registered "${REPO}" "${WORKTREE}"
  refute branch_exists "${REPO}" "grove-task"
  assert branch_exists "${REPO}" "main"
}

@test "rm: works from a subdirectory of the worktree" {
  mkdir -p "${WORKTREE}/sub/dir"
  cd "${WORKTREE}/sub/dir"

  run_grove rm

  assert_success
  assert [ ! -e "${WORKTREE}" ]
  refute branch_exists "${REPO}" "grove-task"
}

@test "rm: --path removes a worktree from anywhere" {
  cd "${TEST_TMP}"

  run_grove rm --path "${WORKTREE}"

  assert_success
  assert [ ! -e "${WORKTREE}" ]
  refute branch_exists "${REPO}" "grove-task"
}

@test "rm: --path removes a worktree from the main repository" {
  cd "${REPO}"

  run_grove rm --path "${WORKTREE}"

  assert_success
  assert [ ! -e "${WORKTREE}" ]
}

@test "rm: removes a worktree with uncommitted changes" {
  printf 'changed\n' > "${WORKTREE}/README.md"
  printf 'new\n' > "${WORKTREE}/untracked.txt"
  printf 'staged\n' > "${WORKTREE}/staged.txt"
  git -C "${WORKTREE}" add staged.txt

  run_grove rm

  assert_success
  assert [ ! -e "${WORKTREE}" ]
  refute branch_exists "${REPO}" "grove-task"
}

@test "rm: deletes a branch that has unmerged commits" {
  commit_file "${WORKTREE}" unmerged.txt "unmerged"

  run_grove rm

  assert_success
  refute branch_exists "${REPO}" "grove-task"
}

@test "rm: leaves other worktrees and branches alone" {
  local other
  other=$(make_worktree "${REPO}" "grove-other")

  run_grove rm

  assert_success
  assert [ -d "${other}" ]
  assert branch_exists "${REPO}" "grove-other"
  assert worktree_registered "${REPO}" "${other}"
}

@test "rm: a detached worktree is removed and no branch is deleted" {
  git -C "${WORKTREE}" checkout --quiet --detach

  run_grove rm

  assert_success
  assert [ ! -e "${WORKTREE}" ]
  assert branch_exists "${REPO}" "grove-task"
  assert branch_exists "${REPO}" "main"
}

@test "rm: a worktree in a custom location is removed" {
  local -r custom="${TEST_TMP}/elsewhere/custom"
  git -C "${REPO}" worktree add --quiet "${custom}" -b feature
  cd "${custom}"

  run_grove rm

  assert_success
  assert [ ! -e "${custom}" ]
  refute branch_exists "${REPO}" "feature"
}

@test "rm: a worktree in a nested directory is removed along with its branch containing a slash" {
  local -r nested="${GROVE_WORKTREES}/feat/thing"
  git -C "${REPO}" worktree add --quiet "${nested}" -b feat/thing
  cd "${nested}"

  run_grove rm

  assert_success
  assert [ ! -e "${nested}" ]
  refute worktree_registered "${REPO}" "${nested}"
  refute branch_exists "${REPO}" "feat/thing"
}

@test "rm: deletes the branch when a tag has the same name" {
  git -C "${REPO}" tag grove-task

  run_grove rm

  assert_success
  refute branch_exists "${REPO}" "grove-task"
}

@test "rm: a locked worktree is left in place without killing its tmux window" {
  enter_tmux
  git -C "${REPO}" worktree lock "${WORKTREE}"
  tmux_add_pane grove 2 0 0 1 %5 "${WORKTREE}"

  run_grove rm --path "${WORKTREE}"

  assert_failure
  assert_tmux_called "cannot remove a locked working tree"
  assert [ -d "${WORKTREE}" ]
  assert branch_exists "${REPO}" "grove-task"
  refute_tmux_called "kill-window"
}

# --- tmux --------------------------------------------------------------------

@test "rm: outside tmux makes no tmux calls" {
  run_grove rm

  assert_success
  refute_any_tmux_call
}

@test "rm: kills the tmux window with a pane in the worktree" {
  enter_tmux
  tmux_fixture pane_current_path "${WORKTREE}"
  tmux_add_pane grove 2 0 0 1 %5 "${WORKTREE}"

  run_grove rm

  assert_success
  assert_tmux_call_exact "kill-window -t grove:2"
}

@test "rm: kills the window when the session name has a space" {
  enter_tmux
  tmux_add_pane "my project" 2 0 0 1 %5 "${WORKTREE}"

  run_grove rm

  assert_success
  assert_tmux_call_exact "kill-window -t 'my project:2'"
}

@test "rm: --path with a trailing slash kills the worktree's window" {
  enter_tmux
  tmux_add_pane grove 4 0 0 1 %5 "${WORKTREE}"
  cd "${REPO}"

  run_grove rm --path "${WORKTREE}/"

  assert_success
  assert [ ! -d "${WORKTREE}" ]
  assert_tmux_call_exact "kill-window -t grove:4"
}

@test "rm: kills a window whose pane is in a subdirectory of the worktree" {
  enter_tmux
  tmux_fixture pane_current_path "${WORKTREE}"
  tmux_add_pane grove 7 0 0 0 %5 "${WORKTREE}/sub/dir"

  run_grove rm

  assert_success
  assert_tmux_call_exact "kill-window -t grove:7"
}

@test "rm: does not kill unrelated windows" {
  enter_tmux
  tmux_fixture pane_current_path "${WORKTREE}"
  tmux_add_pane grove 1 0 0 1 %1 "${REPO}"
  tmux_add_pane grove 2 0 0 1 %5 "${WORKTREE}"
  tmux_add_pane grove 3 0 0 1 %6 "${TEST_TMP}"

  run_grove rm

  assert_equal "$(tmux_call_count "kill-window")" "1"
  assert_tmux_call_exact "kill-window -t grove:2"
}

@test "rm: a path that merely starts with the worktree path does not match" {
  enter_tmux
  local sibling
  sibling=$(make_worktree "${REPO}" "grove-task-two")
  tmux_fixture pane_current_path "${WORKTREE}"
  tmux_add_pane grove 5 0 0 1 %5 "${sibling}"
  tmux_add_pane grove 6 0 0 1 %6 "${sibling}/sub"

  run_grove rm

  assert_success
  refute_tmux_called "kill-window"
  assert [ -d "${sibling}" ]
}

@test "rm: the longer sibling is not removed with the shorter one's window" {
  enter_tmux
  local sibling
  sibling=$(make_worktree "${REPO}" "grove-task-two")
  tmux_add_pane grove 5 0 0 1 %5 "${WORKTREE}"
  tmux_add_pane grove 6 0 0 1 %6 "${sibling}"

  run_grove rm --path "${sibling}"

  assert_success
  assert_tmux_call_exact "kill-window -t grove:6"
  refute_tmux_called "kill-window -t grove:5"
}

@test "rm: kills only the first matching window" {
  enter_tmux
  tmux_fixture pane_current_path "${WORKTREE}"
  tmux_add_pane grove 2 0 0 1 %5 "${WORKTREE}"
  tmux_add_pane grove 3 0 0 1 %6 "${WORKTREE}"

  run_grove rm

  assert_equal "$(tmux_call_count "kill-window")" "1"
  assert_tmux_call_exact "kill-window -t grove:2"
}

@test "rm: without a matching window nothing is killed" {
  enter_tmux
  tmux_fixture pane_current_path "${WORKTREE}"
  tmux_add_pane grove 1 0 0 1 %1 "${REPO}"

  run_grove rm

  assert_success
  refute_tmux_called "kill-window"
}

@test "rm: inside tmux, changes to the pane path before resolving the repository" {
  enter_tmux
  tmux_fixture pane_current_path "${WORKTREE}"
  cd "${TEST_TMP}"

  run_grove rm

  assert_success
  assert [ ! -e "${WORKTREE}" ]
}

@test "rm: inside tmux, errors are shown with display-message" {
  enter_tmux
  tmux_fixture pane_current_path "${REPO}"

  run_grove rm

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: Cannot remove the main worktree. Run this from inside a task worktree.'"
}

@test "rm: --path kills the matching window without asking tmux for the pane path" {
  enter_tmux
  tmux_add_pane grove 2 0 0 1 %5 "${WORKTREE}"
  cd "${TEST_TMP}"

  run_grove rm --path "${WORKTREE}"

  assert_success
  assert_tmux_call_exact "kill-window -t grove:2"
  refute_tmux_called "display-message -p"
}

@test "rm: --path with a stale entry kills the window that was left open" {
  enter_tmux
  tmux_add_pane grove 2 0 0 1 %5 "${WORKTREE}"
  rm -rf "${WORKTREE}"
  cd "${REPO}"

  run_grove rm --path "${WORKTREE}"

  assert_success
  refute worktree_registered "${REPO}" "${WORKTREE}"
  assert_tmux_call_exact "kill-window -t grove:2"
}

@test "rm: works in a repository with many worktrees" {
  add_many_worktrees "${REPO}"

  run_grove rm

  assert_success
  assert [ ! -d "${WORKTREE}" ]
}

@test "rm: --path stops when the worktree's repository link is broken" {
  printf 'gitdir: %s\n' "${TEST_TMP}/missing" > "${WORKTREE}/.git"
  cd "${REPO}"

  run_grove rm --path "${WORKTREE}"

  assert_failure
  assert [ -d "${WORKTREE}" ]
  assert_equal "$(grep -c "null directory\|worktree remove" <<<"${stderr}")" "0"
}
