#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  enter_tmux
  REPO=$(make_repo project)
  WORKTREE=$(make_worktree "${REPO}" "grove-task")
  tmux_fixture pane_current_path "${WORKTREE}"
  # A standard layout: agent left, watcher top-right, shell bottom-right.
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}"
  tmux_add_pane grove 0 50 0 0 %2 "${WORKTREE}"
  tmux_add_pane grove 0 50 25 0 %3 "${WORKTREE}"
  cd "${WORKTREE}"
}

@test "run: outside tmux errors" {
  unset TMUX

  run_grove run

  assert_failure 1
  assert_stderr "Error: grove run must be called from inside tmux."
  refute_any_tmux_call
}

@test "run: outside a git repository errors" {
  mkdir "${TEST_TMP}/plain"
  tmux_fixture pane_current_path "${TEST_TMP}/plain"

  run_grove run

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: Not inside a git repository.'"
  refute_tmux_called "send-keys"
}

@test "run: errors when run.sh is missing" {
  run_grove run

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: .grove/run.sh not found.'"
  refute_tmux_called "send-keys"
}

@test "run: errors when run.sh is not executable" {
  write_grove_script "${WORKTREE}" run.sh 644

  run_grove run

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: .grove/run.sh is not executable.'"
  refute_tmux_called "send-keys"
}

@test "run: sends the script path to the shell pane" {
  write_grove_script "${WORKTREE}" run.sh 755

  run_grove run

  assert_success
  assert_tmux_call_exact "send-keys -t %3 ${WORKTREE}/.grove/run.sh Enter"
}

@test "run: picks the pane with the highest top among panes right of the leftmost column" {
  write_grove_script "${WORKTREE}" run.sh 755
  tmux_add_pane grove 0 50 40 0 %4 "${WORKTREE}"
  tmux_add_pane grove 0 0 30 0 %5 "${WORKTREE}"

  run_grove run

  assert_tmux_called "send-keys -t %4 "
}

@test "run: ignores panes in other windows" {
  write_grove_script "${WORKTREE}" run.sh 755
  tmux_add_pane grove 1 50 90 0 %9 "${REPO}"

  run_grove run

  assert_tmux_called "send-keys -t %3 "
}

@test "run: errors when there is only a leftmost pane" {
  write_grove_script "${WORKTREE}" run.sh 755
  rm "${TMUX_STUB_DIR}/panes"
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}"

  run_grove run

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: No shell pane found.'"
  refute_tmux_called "send-keys"
}

@test "run: errors when the only pane right of the leftmost column is at the top" {
  write_grove_script "${WORKTREE}" run.sh 755
  rm "${TMUX_STUB_DIR}/panes"
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}"
  tmux_add_pane grove 0 50 0 0 %2 "${WORKTREE}"

  run_grove run

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: No shell pane found.'"
}

@test "run: uses the worktree root when the pane is in a subdirectory" {
  write_grove_script "${WORKTREE}" run.sh 755
  mkdir -p "${WORKTREE}/sub"
  tmux_fixture pane_current_path "${WORKTREE}/sub"

  run_grove run

  assert_success
  assert_tmux_call_exact "send-keys -t %3 ${WORKTREE}/.grove/run.sh Enter"
}

@test "run: falls back to the main repository's run.sh" {
  write_grove_script "${REPO}" run.sh 755

  run_grove run

  assert_success
  assert_tmux_call_exact "send-keys -t %3 ${REPO}/.grove/run.sh Enter"
}

@test "run: runs the main repository's script when started from the main repository" {
  write_grove_script "${REPO}" run.sh 755
  tmux_fixture pane_current_path "${REPO}"

  run_grove run

  assert_success
  assert_tmux_call_exact "send-keys -t %3 ${REPO}/.grove/run.sh Enter"
}

@test "run: errors from the main repository when there is no run.sh" {
  tmux_fixture pane_current_path "${REPO}"

  run_grove run

  assert_failure 1
  assert_tmux_called ".grove/run.sh not found."
}
