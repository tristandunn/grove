#!/usr/bin/env bats

set -euo pipefail

# `_rename-prompt` and `_delete-confirm` read their answer from /dev/tty. These
# tests run them inside a pseudo terminal with script(1), typing the answer on
# its standard input. The cases where grove returns before reading the terminal
# use run_grove, because there is no answer to type.

load 'test_helper/common'

setup() {
  if ! command -v script > /dev/null; then
    skip "script(1) from util-linux is needed to provide /dev/tty"
  fi

  common_setup
  REPO=$(make_repo project)
  WORKTREE=$(make_worktree "${REPO}" "grove-task")
  cd "${REPO}"
}

# --- _delete-confirm -----------------------------------------------------------

@test "_delete-confirm: an empty path does nothing and prints no prompt" {
  run_grove _delete-confirm ""

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
  assert [ -d "${WORKTREE}" ]
}

@test "_delete-confirm: no path argument does nothing" {
  run_grove _delete-confirm

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
  assert [ -d "${WORKTREE}" ]
}

@test "_delete-confirm: asks with the worktree's directory name" {
  run_grove_with_tty "n" _delete-confirm "${WORKTREE}"

  assert_success
  assert_output --partial 'Delete "grove-task"? [y/N]'
}

@test "_delete-confirm: y removes the worktree and its branch" {
  run_grove_with_tty "y" _delete-confirm "${WORKTREE}"

  assert_success
  assert [ ! -e "${WORKTREE}" ]
  refute branch_exists "${REPO}" "grove-task"
}

@test "_delete-confirm: Y removes the worktree and its branch" {
  run_grove_with_tty "Y" _delete-confirm "${WORKTREE}"

  assert_success
  assert [ ! -e "${WORKTREE}" ]
  refute branch_exists "${REPO}" "grove-task"
}

@test "_delete-confirm: n cancels" {
  run_grove_with_tty "n" _delete-confirm "${WORKTREE}"

  assert_success
  assert [ -d "${WORKTREE}" ]
  assert branch_exists "${REPO}" "grove-task"
}

@test "_delete-confirm: an empty answer cancels" {
  run_grove_with_tty "" _delete-confirm "${WORKTREE}"

  assert_success
  assert [ -d "${WORKTREE}" ]
}

@test "_delete-confirm: yes (a longer word) cancels" {
  run_grove_with_tty "yes" _delete-confirm "${WORKTREE}"

  assert_success
  assert [ -d "${WORKTREE}" ]
}

@test "_delete-confirm: any other answer cancels" {
  run_grove_with_tty "maybe" _delete-confirm "${WORKTREE}"

  assert_success
  assert [ -d "${WORKTREE}" ]
}

@test "_delete-confirm: confirming kills the tmux window of the worktree" {
  enter_tmux
  tmux_add_pane grove 2 0 0 1 %5 "${WORKTREE}"

  run_grove_with_tty "y" _delete-confirm "${WORKTREE}"

  assert_success
  assert_tmux_call_exact "kill-window -t grove:2"
}

@test "_delete-confirm: cancelling leaves the tmux window alone" {
  enter_tmux
  tmux_add_pane grove 2 0 0 1 %5 "${WORKTREE}"

  run_grove_with_tty "n" _delete-confirm "${WORKTREE}"

  refute_tmux_called "kill-window"
}

# --- _rename-prompt ------------------------------------------------------------

@test "_rename-prompt: an empty path does nothing and prints no prompt" {
  run_grove _rename-prompt ""

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
  assert [ -d "${WORKTREE}" ]
}

@test "_rename-prompt: no path argument does nothing" {
  run_grove _rename-prompt

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
  assert [ -d "${WORKTREE}" ]
}

@test "_rename-prompt: asks with the worktree's directory name" {
  run_grove_with_tty "" _rename-prompt "${WORKTREE}"

  assert_success
  assert_output --partial 'Rename "grove-task" to: '
}

@test "_rename-prompt: renames the worktree to the typed name" {
  run_grove_with_tty "shiny new name" _rename-prompt "${WORKTREE}"

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-shiny-new-name" ]
  assert [ ! -e "${WORKTREE}" ]
  assert branch_exists "${REPO}" "grove-shiny-new-name"
  refute branch_exists "${REPO}" "grove-task"
}

@test "_rename-prompt: an empty answer cancels the rename" {
  run_grove_with_tty "" _rename-prompt "${WORKTREE}"

  assert_success
  assert [ -d "${WORKTREE}" ]
  assert branch_exists "${REPO}" "grove-task"
}

@test "_rename-prompt: a name that slugifies to nothing fails and changes nothing" {
  run_grove_with_tty "!!!" _rename-prompt "${WORKTREE}"

  assert_failure 1
  assert [ -d "${WORKTREE}" ]
  assert branch_exists "${REPO}" "grove-task"
}

@test "_rename-prompt: renames the tmux window too" {
  enter_tmux
  tmux_add_pane grove 2 0 0 1 %5 "${GROVE_WORKTREES}/grove-fresh"

  run_grove_with_tty "fresh" _rename-prompt "${WORKTREE}"

  assert_success
  assert_tmux_call_exact "rename-window -t grove:2 grove-fresh"
}
