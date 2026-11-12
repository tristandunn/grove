#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  cd "${TEST_TMP}"
}

# `grove new` outside a repository is the simplest way to reach error().

@test "error: without TMUX prints Error: to stderr and exits 1" {
  run_grove new something

  assert_failure 1
  assert_output ""
  assert_stderr "Error: Not inside a git repository."
  refute_any_tmux_call
}

@test "error: with TMUX shows a tmux message and exits 1" {
  enter_tmux

  run_grove new something

  assert_failure 1
  assert_output ""
  assert_equal "${stderr}" ""
  assert_tmux_call_exact "display-message -d 2000 'grove: Not inside a git repository.'"
}
