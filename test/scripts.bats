#!/usr/bin/env bats

set -euo pipefail

# resolve_grove_script is internal. It is exercised through `grove run`
# (run.sh) and `grove new` (setup.sh): the worktree's copy wins, then the main
# repository's copy, otherwise nothing.

load 'test_helper/common'

setup() {
  common_setup
  enter_tmux
  REPO=$(make_repo project)
  tmux_add_pane grove 0 0 0 1 %1 "${TEST_TMP}"
  tmux_add_pane grove 0 50 0 0 %2 "${TEST_TMP}"
  tmux_add_pane grove 0 50 25 0 %3 "${TEST_TMP}"
}

@test "scripts: run.sh in the worktree wins over the main repository's" {
  commit_grove_script "${REPO}" run.sh 755
  local worktree
  worktree=$(make_worktree "${REPO}" "grove-task")
  tmux_fixture pane_current_path "${worktree}"
  cd "${worktree}"

  run_grove run

  assert_success
  assert_tmux_call_exact "send-keys -t %3 ${worktree}/.grove/run.sh Enter"
  refute_tmux_called "${REPO}/.grove/run.sh"
}

@test "scripts: a non-executable worktree run.sh wins over an executable main one" {
  commit_grove_script "${REPO}" run.sh 644
  chmod 755 "${REPO}/.grove/run.sh"
  local worktree
  worktree=$(make_worktree "${REPO}" "grove-task")
  tmux_fixture pane_current_path "${worktree}"
  cd "${worktree}"

  run_grove run

  assert_failure 1
  assert_tmux_called ".grove/run.sh is not executable."
}

@test "scripts: the main repository's run.sh is used when the worktree has none" {
  write_grove_script "${REPO}" run.sh 755
  local worktree
  worktree=$(make_worktree "${REPO}" "grove-task")
  tmux_fixture pane_current_path "${worktree}"
  cd "${worktree}"

  run_grove run

  assert_success
  assert_tmux_call_exact "send-keys -t %3 ${REPO}/.grove/run.sh Enter"
}

@test "scripts: neither location having run.sh is an error" {
  local worktree
  worktree=$(make_worktree "${REPO}" "grove-task")
  tmux_fixture pane_current_path "${worktree}"
  cd "${worktree}"

  run_grove run

  assert_failure 1
  assert_tmux_called ".grove/run.sh not found."
}

@test "scripts: scripts are looked up by name, so setup.sh does not satisfy run.sh" {
  write_grove_script "${REPO}" setup.sh 755
  local worktree
  worktree=$(make_worktree "${REPO}" "grove-task")
  tmux_fixture pane_current_path "${worktree}"
  cd "${worktree}"

  run_grove run

  assert_failure 1
  assert_tmux_called ".grove/run.sh not found."
}

@test "scripts: a worktree reached through an absolute git-common-dir finds the main repository" {
  write_grove_script "${REPO}" run.sh 755
  local worktree
  worktree=$(make_worktree "${REPO}" "grove-task")
  # Linked worktrees report an absolute --git-common-dir.
  assert [ "$(git -C "${worktree}" rev-parse --git-common-dir)" = "${REPO}/.git" ]
  tmux_fixture pane_current_path "${worktree}"

  run_grove run

  assert_success
  assert_tmux_called "${REPO}/.grove/run.sh"
}

@test "scripts: the main repository reports a relative git-common-dir and still resolves" {
  write_grove_script "${REPO}" run.sh 755
  assert [ "$(git -C "${REPO}" rev-parse --git-common-dir)" = ".git" ]
  tmux_fixture pane_current_path "${REPO}"

  run_grove run

  assert_success
  assert_tmux_called "${REPO}/.grove/run.sh"
}

@test "scripts: a relative git-common-dir with no script in the main repository finds nothing" {
  tmux_fixture pane_current_path "${REPO}"

  run_grove run

  assert_failure 1
  assert_tmux_called ".grove/run.sh not found."
}

@test "scripts: setup.sh from the worktree wins when creating a task" {
  unset TMUX
  commit_grove_script "${REPO}" setup.sh 755
  cd "${REPO}"

  run_grove new thing

  assert_tmux_called "send-keys -t %3 ${GROVE_WORKTREES}/grove-thing/.grove/setup.sh Enter"
}

@test "scripts: setup.sh falls back to the main repository when creating a task" {
  unset TMUX
  write_grove_script "${REPO}" setup.sh 755
  cd "${REPO}"

  run_grove new thing

  assert_tmux_called "send-keys -t %3 ${REPO}/.grove/setup.sh Enter"
}

@test "scripts: creating a task with no setup.sh sends nothing to the shell pane" {
  unset TMUX
  cd "${REPO}"

  run_grove new thing

  refute_tmux_called "send-keys -t %3"
}
