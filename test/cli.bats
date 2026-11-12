#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
}

@test "cli: -v prints the version from the script" {
  local expected
  expected=$(sed -n 's/^readonly VERSION="\(.*\)"$/\1/p' "${GROVE_BIN}")

  run_grove -v

  assert_success
  assert_output "grove version ${expected}"
}

@test "cli: --version prints the version from the script" {
  local expected
  expected=$(sed -n 's/^readonly VERSION="\(.*\)"$/\1/p' "${GROVE_BIN}")

  run_grove --version

  assert_success
  assert_output "grove version ${expected}"
}

@test "cli: the version in the script is not empty" {
  run grep -c '^readonly VERSION="[0-9]\+\.[0-9]\+\.[0-9]\+"$' "${GROVE_BIN}"

  assert_output "1"
}

@test "cli: -h prints usage to stdout and exits 0" {
  run_grove -h

  assert_success
  assert_output --partial "Usage: grove <command> [args]"
  assert_equal "${stderr}" ""
}

@test "cli: --help prints usage to stdout and exits 0" {
  run_grove --help

  assert_success
  assert_output --partial "Usage: grove <command> [args]"
  assert_equal "${stderr}" ""
}

@test "cli: help prints usage to stdout and exits 0" {
  run_grove help

  assert_success
  assert_output --partial "Usage: grove <command> [args]"
  assert_equal "${stderr}" ""
}

@test "cli: usage documents every command and environment variable" {
  run_grove help

  assert_output --partial "new <task-name>"
  assert_output --partial "rename <new-name>"
  assert_output --partial "add-agent"
  assert_output --partial "run "
  assert_output --partial "switch "
  assert_output --partial "rm "
  assert_output --partial "GROVE_AGENT"
  assert_output --partial "GROVE_PREFIX"
  assert_output --partial "GROVE_ROOT"
  assert_output --partial "GROVE_WORKTREES"
  assert_output --partial "GROVE_WORKSPACE_NAME"
}

@test "cli: no arguments prints usage to stderr and exits 1" {
  run_grove

  assert_failure 1
  assert_output ""
  assert_stderr --partial "Usage: grove <command> [args]"
}

@test "cli: a single unknown word prints usage to stderr and exits 1" {
  run_grove frobnicate

  assert_failure 1
  assert_output ""
  assert_stderr --partial "Usage: grove <command> [args]"
}

@test "cli: an empty argument prints usage to stderr and exits 1" {
  run_grove ""

  assert_failure 1
  assert_stderr --partial "Usage: grove <command> [args]"
}

@test "cli: several words are treated as a task name" {
  local repo
  repo=$(make_repo project)
  cd "${repo}"

  run_grove fix login bug

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-fix-login-bug" ]
  assert branch_exists "${repo}" "grove-fix-login-bug"
}

@test "cli: one argument containing a space is treated as a task name" {
  local repo
  repo=$(make_repo project)
  cd "${repo}"

  run_grove "fix login bug"

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-fix-login-bug" ]
}

@test "cli: several words outside a repository fail with the new-command error" {
  cd "${TEST_TMP}"

  run_grove fix login bug

  assert_failure 1
  assert_stderr "Error: Not inside a git repository."
}

@test "cli: a known command name still wins over the task-name shortcut" {
  run_grove help me

  assert_success
  assert_output --partial "Usage: grove <command> [args]"
}
