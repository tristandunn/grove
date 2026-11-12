#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  REPO=$(make_repo project)
  cd "${REPO}"
}

# --- Arguments and environment ----------------------------------------------

@test "new: no arguments prints usage to stderr and exits 1" {
  run_grove new

  assert_failure 1
  assert_output ""
  assert_stderr "Usage: grove new <task-name>"
  refute_any_tmux_call
}

@test "new: outside a git repository errors" {
  cd "${TEST_TMP}"

  run_grove new something

  assert_failure 1
  assert_stderr "Error: Not inside a git repository."
  refute_any_tmux_call
}

@test "new: inside tmux, errors are shown with display-message" {
  enter_tmux
  cd "${TEST_TMP}"

  run_grove new something

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: Not inside a git repository.'"
}

# --- Slugs -------------------------------------------------------------------

@test "new: slug lowercases uppercase letters" {
  run_grove new "FIX Login"

  assert_success
  assert branch_exists "${REPO}" "grove-fix-login"
}

@test "new: slug turns spaces into hyphens" {
  run_grove new "one two three"

  assert_success
  assert branch_exists "${REPO}" "grove-one-two-three"
}

@test "new: slug joins multiple arguments with hyphens" {
  run_grove new one two three

  assert_success
  assert branch_exists "${REPO}" "grove-one-two-three"
}

@test "new: slug strips punctuation" {
  run_grove new "Fix: login/auth (v2)!"

  assert_success
  assert branch_exists "${REPO}" "grove-fix-loginauth-v2"
}

@test "new: slug keeps digits" {
  run_grove new "issue 42"

  assert_success
  assert branch_exists "${REPO}" "grove-issue-42"
}

@test "new: slug strips non-ASCII characters" {
  run_grove new "Café Über Naïve"

  assert_success
  assert branch_exists "${REPO}" "grove-caf-ber-nave"
}

@test "new: slug collapses repeated hyphens and spaces" {
  run_grove new "a --  -- b"

  assert_success
  assert branch_exists "${REPO}" "grove-a-b"
}

@test "new: slug trims leading and trailing hyphens" {
  run_grove new "--Foo--  bar--"

  assert_success
  assert branch_exists "${REPO}" "grove-foo-bar"
}

@test "new: a name made only of punctuation errors with an empty slug" {
  run_grove new "!!! ???"

  assert_failure 1
  assert_stderr "Error: Task name produced an empty slug."
  refute_any_tmux_call
  assert [ ! -e "${GROVE_WORKTREES}" ]
}

@test "new: a name made only of non-ASCII characters errors with an empty slug" {
  run_grove new "日本語"

  assert_failure 1
  assert_stderr "Error: Task name produced an empty slug."
}

@test "new: a name made only of hyphens errors with an empty slug" {
  run_grove new -- "---"

  assert_failure 1
  assert_stderr "Error: Task name produced an empty slug."
}

# --- Worktree creation -------------------------------------------------------

@test "new: creates the worktree and branch with the default prefix" {
  run_grove new fix login bug

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-fix-login-bug" ]
  assert branch_exists "${REPO}" "grove-fix-login-bug"
  assert worktree_registered "${REPO}" "${GROVE_WORKTREES}/grove-fix-login-bug"
  assert_equal "$(git -C "${GROVE_WORKTREES}/grove-fix-login-bug" rev-parse --abbrev-ref HEAD)" "grove-fix-login-bug"
}

@test "new: prints nothing on success when run inside tmux" {
  enter_tmux

  run_grove new quiet

  assert_success
  assert_output ""
}

@test "new: branches from the current branch of the main worktree" {
  git checkout --quiet -b develop
  commit_file "${REPO}" develop.txt "develop"

  run_grove new feature

  assert_success
  assert_equal "$(git -C "${GROVE_WORKTREES}/grove-feature" rev-parse HEAD)" "$(git -C "${REPO}" rev-parse develop)"
  assert [ -f "${GROVE_WORKTREES}/grove-feature/develop.txt" ]
}

@test "new: run from a worktree, branches from the main worktree not the current one" {
  local worktree
  worktree=$(make_worktree "${REPO}" "grove-other")
  commit_file "${worktree}" other.txt "other"
  cd "${worktree}"

  run_grove new second

  assert_success
  assert_equal "$(git -C "${GROVE_WORKTREES}/grove-second" rev-parse HEAD)" "$(git -C "${REPO}" rev-parse main)"
  assert [ ! -e "${GROVE_WORKTREES}/grove-second/other.txt" ]
}

@test "new: run from a subdirectory of the repository works" {
  mkdir -p "${REPO}/deep/er"
  cd "${REPO}/deep/er"

  run_grove new nested

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-nested" ]
}

# --- Prefix and location -----------------------------------------------------

@test "new: GROVE_PREFIX overrides the prefix" {
  GROVE_PREFIX="task-" run_grove new thing

  assert_success
  assert [ -d "${GROVE_WORKTREES}/task-thing" ]
  assert branch_exists "${REPO}" "task-thing"
  assert [ ! -e "${GROVE_WORKTREES}/grove-thing" ]
}

@test "new: an empty GROVE_PREFIX gives an empty prefix" {
  GROVE_PREFIX="" run_grove new thing

  assert_success
  assert [ -d "${GROVE_WORKTREES}/thing" ]
  assert branch_exists "${REPO}" "thing"
}

@test "new: a prefix ending in a slash nests the worktree in a subdirectory" {
  GROVE_PREFIX="feat/" run_grove new thing

  assert_success
  assert [ -d "${GROVE_WORKTREES}/feat/thing" ]
  assert branch_exists "${REPO}" "feat/thing"
  assert_tmux_called "-n thing "
}

@test "new: GROVE_ROOT sets the location when GROVE_WORKTREES is unset" {
  unset GROVE_WORKTREES
  export GROVE_ROOT="${TEST_TMP}/elsewhere"

  run_grove new thing

  assert_success
  assert [ -d "${TEST_TMP}/elsewhere/worktrees/grove-thing" ]
}

@test "new: GROVE_WORKTREES sets the location" {
  export GROVE_WORKTREES="${TEST_TMP}/custom"

  run_grove new thing

  assert_success
  assert [ -d "${TEST_TMP}/custom/grove-thing" ]
}

@test "new: GROVE_WORKTREES wins over GROVE_ROOT" {
  export GROVE_ROOT="${TEST_TMP}/ignored"
  export GROVE_WORKTREES="${TEST_TMP}/custom"

  run_grove new thing

  assert_success
  assert [ -d "${TEST_TMP}/custom/grove-thing" ]
  assert [ ! -e "${TEST_TMP}/ignored" ]
}

@test "new: with neither variable set, uses HOME/Sites/worktrees" {
  unset GROVE_ROOT GROVE_WORKTREES

  run_grove new thing

  assert_success
  assert [ -d "${HOME}/Sites/worktrees/grove-thing" ]
}

# --- Collisions --------------------------------------------------------------

@test "new: an existing branch fails without creating anything" {
  git branch grove-taken

  run_grove new taken

  assert_failure
  assert_output ""
  assert_stderr --partial "grove-taken"
  assert [ ! -e "${GROVE_WORKTREES}/grove-taken" ]
  refute_any_tmux_call
}

@test "new: an existing path fails and leaves it untouched" {
  mkdir -p "${GROVE_WORKTREES}/grove-taken"
  printf 'keep' > "${GROVE_WORKTREES}/grove-taken/file"

  run_grove new taken

  assert_failure
  assert_stderr --partial "already exists"
  assert_equal "$(cat "${GROVE_WORKTREES}/grove-taken/file")" "keep"
  refute_any_tmux_call
}

@test "new: an existing path does not leave a stray branch behind" {
  mkdir -p "${GROVE_WORKTREES}/grove-taken"

  run_grove new taken

  assert_failure
  refute branch_exists "${REPO}" "grove-taken"
}

@test "new: creating the same task twice fails the second time" {
  run_grove new twice
  assert_success

  run_grove new twice

  assert_failure
  assert_equal "$(git -C "${REPO}" worktree list | wc -l)" "2"
}

@test "new: a collision inside tmux is not shown as a tmux message" {
  # The git failure bypasses error(), so tmux users see nothing in the status
  # line. Recorded here as current behavior.
  enter_tmux
  git branch grove-taken

  run_grove new taken

  assert_failure
  refute_tmux_called "display-message"
}

@test "new: a detached HEAD in the main worktree fails without creating anything" {
  git checkout --quiet --detach

  run_grove new thing

  assert_failure
  assert [ ! -e "${GROVE_WORKTREES}/grove-thing" ]
  refute_any_tmux_call
}

@test "new: a repository with no commits fails without creating anything" {
  local -r fresh="${TEST_TMP}/fresh"
  git init --quiet "${fresh}"
  cd "${fresh}"

  run_grove new thing

  assert_failure
  assert_stderr --partial "fatal"
  assert [ ! -e "${GROVE_WORKTREES}" ]
  refute_any_tmux_call
}

@test "new: a task name too long for a file name fails without creating anything" {
  local name
  name=$(printf 'word%.0s ' {1..80})

  run_grove new "${name}"

  assert_failure
  assert_equal "$(git branch --list 'grove-*')" ""
  assert [ ! -e "${GROVE_WORKTREES}" ]
  refute_any_tmux_call
}

@test "new: a GROVE_PREFIX that makes an invalid branch name fails without creating anything" {
  GROVE_PREFIX="bad..prefix-" run_grove new thing

  assert_failure
  assert_stderr --partial "bad..prefix-thing"
  assert [ ! -e "${GROVE_WORKTREES}" ]
  refute_any_tmux_call
}

# --- tmux --------------------------------------------------------------------

@test "new: creates a detached session when none exists" {
  run_grove new thing

  assert_success
  assert_tmux_call_exact "has-session -t project"
  assert_tmux_call_exact "new-session -d -s project -n grove-thing -c ${GROVE_WORKTREES}/grove-thing -x 120 -y 40 -P -F #{pane_id}"
  refute_tmux_called "new-window"
}

@test "new: adds a window after the current one when the session exists" {
  tmux_fixture_session

  run_grove new thing

  assert_success
  assert_tmux_call_exact "new-window -a -t project -n grove-thing -c ${GROVE_WORKTREES}/grove-thing -P -F #{pane_id}"
  refute_tmux_called "new-session"
}

@test "new: the session name replaces dots and colons with underscores" {
  local repo
  repo=$(make_repo "my.proj:v2")
  cd "${repo}"

  run_grove new thing

  assert_success
  assert_tmux_called "has-session -t my_proj_v2"
  assert_tmux_called "new-session -d -s my_proj_v2 -n grove-thing"
}

@test "new: run from a worktree, the session and project come from the main repo" {
  local worktree
  worktree=$(make_worktree "${REPO}" "grove-other")
  cd "${worktree}"

  run_grove new second

  assert_success
  assert_tmux_called "has-session -t project"
  assert_tmux_called "new-session -d -s project -n grove-second"
  refute_tmux_called "grove-other"
}

@test "new: uses the client size for the new session" {
  tmux_fixture client_width 200
  tmux_fixture client_height 50

  run_grove new thing

  assert_tmux_called "-x 200 -y 50 -P"
}

@test "new: falls back to tput when the client size is not numeric" {
  tmux_fixture client_width "error"
  tmux_fixture client_height ""

  run_grove new thing

  assert_tmux_called "-x 123 -y 45 -P"
}

@test "new: falls back to 200x48 when tput fails as well" {
  tmux_fixture client_width "error"
  tmux_fixture client_height "error"
  export TPUT_STUB_FAIL=1

  run_grove new thing

  assert_tmux_called "-x 200 -y 48 -P"
}

@test "new: falls back to tput for the height only when only the height is bad" {
  tmux_fixture client_width 150
  tmux_fixture client_height "x"

  run_grove new thing

  assert_tmux_called "-x 150 -y 45 -P"
}

@test "new: selects the new window" {
  tmux_fixture session_name project
  tmux_fixture window_index 3

  run_grove new thing

  assert_tmux_call_exact "display-message -t %1 -p #{session_name}:#{window_index}"
  assert_tmux_call_exact "select-window -t project:3"
}

@test "new: builds the three-pane layout around the new pane" {
  run_grove new thing

  assert_tmux_called "split-window -t %1 -h -l 45% -c ${GROVE_WORKTREES}/grove-thing"
  assert_tmux_called "split-window -t %2 -v -l 50% -c ${GROVE_WORKTREES}/grove-thing -e GROVE_WORKSPACE_NAME=thing"
}

@test "new: runs the agent in the left pane without --continue" {
  run_grove new thing

  assert_tmux_call_exact "send-keys -t %1 claude Enter"
}

@test "new: runs grove file-watch in the watcher pane" {
  run_grove new thing

  assert_tmux_call_exact "send-keys -t %2 'grove file-watch' Enter"
}

@test "new: GROVE_AGENT is honored" {
  GROVE_AGENT=codex run_grove new thing

  assert_tmux_call_exact "send-keys -t %1 codex Enter"
}

@test "new: reuses the session with exactly the project's name" {
  tmux_add_session "project"
  tmux_add_session "project-docs"

  run_grove new thing

  assert_success
  assert_tmux_called "new-window"
  refute_tmux_called "new-session"
}

@test "new: keeps paths and the session name with spaces intact" {
  local repo
  repo=$(make_repo "my project")
  cd "${repo}"
  export GROVE_WORKTREES="${TEST_TMP}/my worktrees"

  run_grove new thing

  assert_success
  assert [ -d "${GROVE_WORKTREES}/grove-thing" ]
  assert_tmux_call_exact "new-session -d -s 'my project' -n grove-thing -c '${GROVE_WORKTREES}/grove-thing' -x 120 -y 40 -P -F #{pane_id}"
  assert_tmux_called "split-window -t %1 -h -l 45% -c '${GROVE_WORKTREES}/grove-thing'"
}

@test "new: outside tmux, attaches to the session" {
  run_grove new thing

  assert_success
  assert_tmux_call_exact "attach-session -t project"
}

@test "new: inside tmux, does not attach" {
  enter_tmux

  run_grove new thing

  assert_success
  refute_tmux_called "attach-session"
}

# --- .grove/setup.sh ---------------------------------------------------------

@test "new: runs an executable setup.sh from the worktree in the shell pane" {
  commit_grove_script "${REPO}" setup.sh 755

  run_grove new thing

  assert_success
  assert_tmux_call_exact "send-keys -t %3 ${GROVE_WORKTREES}/grove-thing/.grove/setup.sh Enter"
}

@test "new: warns when the worktree's setup.sh is not executable" {
  commit_grove_script "${REPO}" setup.sh 644

  run_grove new thing

  assert_success
  assert_tmux_call_exact "display-message -d 3000 'grove: .grove/setup.sh is not executable.'"
  refute_tmux_called "setup.sh Enter"
}

@test "new: does nothing when there is no setup.sh" {
  run_grove new thing

  assert_success
  refute_tmux_called "setup.sh"
  refute_tmux_called "display-message -d"
}

@test "new: falls back to the main repository's setup.sh" {
  write_grove_script "${REPO}" setup.sh 755

  run_grove new thing

  assert_success
  assert [ ! -e "${GROVE_WORKTREES}/grove-thing/.grove" ]
  assert_tmux_call_exact "send-keys -t %3 ${REPO}/.grove/setup.sh Enter"
}

@test "new: warns when the main repository's setup.sh is not executable" {
  write_grove_script "${REPO}" setup.sh 644

  run_grove new thing

  assert_success
  assert_tmux_call_exact "display-message -d 3000 'grove: .grove/setup.sh is not executable.'"
  refute_tmux_called "setup.sh Enter"
}

@test "new: an executable worktree setup.sh wins over a non-executable main one" {
  commit_grove_script "${REPO}" setup.sh 755
  chmod 644 "${REPO}/.grove/setup.sh"

  run_grove new thing

  assert_success
  assert_tmux_call_exact "send-keys -t %3 ${GROVE_WORKTREES}/grove-thing/.grove/setup.sh Enter"
  refute_tmux_called "${REPO}/.grove/setup.sh"
  refute_tmux_called "is not executable"
}

@test "new: a non-executable worktree setup.sh wins over an executable main one" {
  commit_grove_script "${REPO}" setup.sh 644
  chmod 755 "${REPO}/.grove/setup.sh"

  run_grove new thing

  assert_success
  assert_tmux_called "is not executable"
  refute_tmux_called "setup.sh Enter"
}

@test "new: setup.sh is sent to the shell pane, not the agent pane" {
  commit_grove_script "${REPO}" setup.sh 755

  run_grove new thing

  assert_equal "$(tmux_call_count "send-keys -t %1 ")" "1"
  assert_equal "$(tmux_call_count "setup.sh Enter")" "1"
}

@test "new: the command sent for setup.sh runs the script" {
  commit_grove_script "${REPO}" setup.sh 755

  run_grove new thing

  assert_success
  run bash -c "$(tmux_sent_keys %3)"
  assert_output "setup.sh"
}
