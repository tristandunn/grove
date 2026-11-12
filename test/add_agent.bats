#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  enter_tmux
  REPO=$(make_repo project)
  WORKTREE=$(make_worktree "${REPO}" "grove-task")
  # The new pane will be %11.
  tmux_fixture pane_counter 10
  tmux_fixture pane_current_path "${WORKTREE}"
  cd "${WORKTREE}"
}

@test "add-agent: splits vertically in the leftmost pane" {
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}"
  tmux_add_pane grove 0 50 0 0 %2 "${WORKTREE}"
  tmux_add_pane grove 0 50 25 0 %3 "${WORKTREE}"

  run_grove add-agent

  assert_success
  assert_tmux_call_exact "split-window -v -t %1 -c ${WORKTREE} -P -F #{pane_id}"
}

@test "add-agent: starts the default agent in the new pane" {
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}"

  run_grove add-agent

  assert_tmux_call_exact "send-keys -t %11 claude Enter"
}

@test "add-agent: GROVE_AGENT is honored" {
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}"

  GROVE_AGENT="codex --yolo" run_grove add-agent

  assert_tmux_call_exact "send-keys -t %11 'codex --yolo' Enter"
}

@test "add-agent: an empty GROVE_AGENT falls back to claude" {
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}"

  GROVE_AGENT="" run_grove add-agent

  assert_tmux_call_exact "send-keys -t %11 claude Enter"
}

@test "add-agent: does not add --continue" {
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}"

  run_grove add-agent

  refute_tmux_called "--continue"
}

@test "add-agent: pauses before sending keystrokes" {
  export SLEEP_STUB_LOG="${TEST_TMP}/sleep.log"
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}"

  run_grove add-agent

  assert_equal "$(cat "${SLEEP_STUB_LOG}")" "0.3"
}

@test "add-agent: prefers the active pane in the leftmost column" {
  tmux_add_pane grove 0 0 0 0 %1 "${WORKTREE}"
  tmux_add_pane grove 0 0 25 1 %2 "${WORKTREE}"
  tmux_add_pane grove 0 50 0 0 %3 "${WORKTREE}"

  run_grove add-agent

  assert_tmux_called "split-window -v -t %2 "
}

@test "add-agent: falls back to the first leftmost pane when the active pane is elsewhere" {
  tmux_add_pane grove 0 0 0 0 %1 "${WORKTREE}"
  tmux_add_pane grove 0 0 25 0 %2 "${WORKTREE}"
  tmux_add_pane grove 0 50 0 1 %3 "${WORKTREE}"

  run_grove add-agent

  assert_success
  assert_tmux_called "split-window -v -t %1 "
}

@test "add-agent: ignores panes in other windows" {
  tmux_add_pane grove 1 0 0 1 %9 "${REPO}"
  tmux_add_pane grove 0 0 0 0 %1 "${WORKTREE}"

  run_grove add-agent

  assert_tmux_called "split-window -v -t %1 "
}

@test "add-agent: starts in the worktree root when the pane is in a subdirectory" {
  mkdir -p "${WORKTREE}/sub/dir"
  tmux_fixture pane_current_path "${WORKTREE}/sub/dir"
  tmux_add_pane grove 0 0 0 1 %1 "${WORKTREE}/sub/dir"

  run_grove add-agent

  assert_tmux_called "-c ${WORKTREE} -P"
  refute_tmux_called "-c ${WORKTREE}/sub"
}

@test "add-agent: starts in the pane path when it is not inside a repository" {
  mkdir "${TEST_TMP}/plain"
  tmux_fixture pane_current_path "${TEST_TMP}/plain"
  tmux_add_pane grove 0 0 0 1 %1 "${TEST_TMP}/plain"

  run_grove add-agent

  assert_success
  assert_tmux_called "-c ${TEST_TMP}/plain -P"
}

@test "add-agent: starts in the repository root when run in the main repository" {
  mkdir "${REPO}/sub"
  tmux_fixture pane_current_path "${REPO}/sub"
  tmux_add_pane grove 0 0 0 1 %1 "${REPO}/sub"

  run_grove add-agent

  assert_tmux_called "-c ${REPO} -P"
}
