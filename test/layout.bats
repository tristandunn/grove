#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  REPO=$(make_repo project)
  WORKTREE=$(make_worktree "${REPO}" "grove-feature")
  # Pane %1 is the left pane the caller already has; new panes start at %2.
  tmux_fixture pane_counter 1
  cd "${TEST_TMP}"
}

@test "layout: no arguments prints usage to stderr and exits 1" {
  run_grove layout

  assert_failure 1
  assert_output ""
  assert_stderr "Usage: grove layout <pane-id> <worktree-path> [--continue]"
  refute_any_tmux_call
}

@test "layout: one argument prints usage and exits 1" {
  run_grove layout %1

  assert_failure 1
  assert_stderr "Usage: grove layout <pane-id> <worktree-path> [--continue]"
}

@test "layout: four arguments print usage and exits 1" {
  run_grove layout %1 "${WORKTREE}" --continue extra

  assert_failure 1
  assert_stderr "Usage: grove layout <pane-id> <worktree-path> [--continue]"
}

@test "layout: splits right at 45% and then splits the watcher at 50%" {
  run_grove layout %1 "${WORKTREE}"

  assert_success
  assert_tmux_call_exact "split-window -t %1 -h -l 45% -c ${WORKTREE} -P -F #{pane_id}"
  assert_tmux_call_exact "split-window -t %2 -v -l 50% -c ${WORKTREE} -e GROVE_WORKSPACE_NAME=feature -P -F #{pane_id}"
}

@test "layout: prints the shell pane ID to stdout" {
  run_grove layout %1 "${WORKTREE}"

  assert_success
  assert_output "%3"
}

@test "layout: runs the file watcher in the watcher pane" {
  run_grove layout %1 "${WORKTREE}"

  assert_tmux_call_exact "send-keys -t %2 'grove file-watch' Enter"
}

@test "layout: runs claude in the left pane by default" {
  run_grove layout %1 "${WORKTREE}"

  assert_tmux_call_exact "send-keys -t %1 claude Enter"
}

@test "layout: GROVE_AGENT overrides the agent" {
  GROVE_AGENT="codex --fast" run_grove layout %1 "${WORKTREE}"

  assert_tmux_call_exact "send-keys -t %1 'codex --fast' Enter"
}

@test "layout: an empty GROVE_AGENT falls back to claude" {
  GROVE_AGENT="" run_grove layout %1 "${WORKTREE}" --continue

  assert_tmux_call_exact "send-keys -t %1 'claude --continue' Enter"
}

@test "layout: --continue appends --continue to the default agent" {
  run_grove layout %1 "${WORKTREE}" --continue

  assert_tmux_call_exact "send-keys -t %1 'claude --continue' Enter"
}

@test "layout: --continue appends --continue to a custom agent" {
  GROVE_AGENT=codex run_grove layout %1 "${WORKTREE}" --continue

  assert_tmux_call_exact "send-keys -t %1 'codex --continue' Enter"
}

@test "layout: any other third argument does not add --continue" {
  run_grove layout %1 "${WORKTREE}" --other

  assert_tmux_call_exact "send-keys -t %1 claude Enter"
}

@test "layout: focuses the left pane at the end" {
  run_grove layout %1 "${WORKTREE}"

  assert_success
  assert_equal "$(tmux_calls | tail -1)" "select-pane -t %1"
}

@test "layout: pauses before sending keystrokes" {
  export SLEEP_STUB_LOG="${TEST_TMP}/sleep.log"

  run_grove layout %1 "${WORKTREE}"

  assert_equal "$(cat "${SLEEP_STUB_LOG}")" "0.3"
}

@test "layout: the workspace name has the default prefix stripped" {
  run_grove layout %1 "${WORKTREE}"

  assert_tmux_called "GROVE_WORKSPACE_NAME=feature "
}

@test "layout: a custom prefix is stripped from the workspace name" {
  local worktree
  worktree=$(make_worktree "${REPO}" "task-one")

  GROVE_PREFIX="task-" run_grove layout %1 "${worktree}"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=one "
}

@test "layout: an empty prefix leaves the whole branch as the workspace name" {
  GROVE_PREFIX="" run_grove layout %1 "${WORKTREE}"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=grove-feature "
}

@test "layout: a detached HEAD yields an empty workspace name" {
  git -C "${WORKTREE}" checkout --quiet --detach

  run_grove layout %1 "${WORKTREE}"

  assert_success
  assert_tmux_called "-e GROVE_WORKSPACE_NAME= -P"
}

@test "layout: a path that is not a repository yields an empty workspace name" {
  mkdir "${TEST_TMP}/plain"

  run_grove layout %1 "${TEST_TMP}/plain"

  assert_success
  assert_tmux_called "-e GROVE_WORKSPACE_NAME= -P"
}
