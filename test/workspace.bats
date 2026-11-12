#!/usr/bin/env bats

set -euo pipefail

# workspace_name is internal, so it is exercised through `grove layout`, which
# passes it to the shell pane as GROVE_WORKSPACE_NAME.

load 'test_helper/common'

setup() {
  common_setup
  REPO=$(make_repo project)
  tmux_fixture pane_counter 1
  cd "${TEST_TMP}"
}

workspace_for_branch() {
  local -r branch="$1"

  local worktree
  worktree=$(make_worktree "${REPO}" "${branch}" "${TEST_TMP}/wt-${branch//\//_}")

  run_grove layout %1 "${worktree}"
}

@test "workspace_name: strips the default prefix" {
  workspace_for_branch "grove-fix-login"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=fix-login -P"
}

@test "workspace_name: leaves a branch without the prefix unchanged" {
  workspace_for_branch "feature"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=feature -P"
}

@test "workspace_name: an empty prefix strips nothing" {
  GROVE_PREFIX="" workspace_for_branch "grove-x"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=grove-x -P"
}

@test "workspace_name: only strips the prefix at the start of the name" {
  workspace_for_branch "my-grove-x"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=my-grove-x -P"
}

@test "workspace_name: a custom prefix is honored" {
  GROVE_PREFIX="task-" workspace_for_branch "task-a"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=a -P"
}

@test "workspace_name: the default prefix is not stripped when a custom one is set" {
  GROVE_PREFIX="task-" workspace_for_branch "grove-a"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=grove-a -P"
}

@test "workspace_name: a prefix containing a slash is stripped literally" {
  GROVE_PREFIX="feat/" workspace_for_branch "feat/a"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=a -P"
}

@test "workspace_name: prefix characters are not treated as a glob pattern" {
  GROVE_PREFIX="g*-" workspace_for_branch "grove-a"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME=grove-a -P"
}

@test "workspace_name: a branch equal to the prefix gives an empty name" {
  GROVE_PREFIX="task" workspace_for_branch "task"

  assert_tmux_called "-e GROVE_WORKSPACE_NAME= -P"
}
