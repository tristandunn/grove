#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  REPO=$(make_repo project)
}

# Make the stub fzf "select" the named worktree's entry from `grove switch
# --list`, run from the current directory.
select_entry() {
  local -r name="$1"

  run_grove switch --list

  local line
  for line in "${lines[@]}"; do
    if [[ "$(printf '%s\n' "${line}" | entry_name)" == "${name}" ]]; then
      fzf_select "${line}"
      return
    fi
  done

  fail "no switcher entry named ${name}"
}

# --- --list inside a project -------------------------------------------------

@test "switch --list: inside a project lists its non-main worktrees only" {
  make_worktree "${REPO}" grove-a > /dev/null
  make_worktree "${REPO}" grove-b > /dev/null
  cd "${REPO}"

  run_grove switch --list

  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "a"
  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_name)" "b"
}

@test "switch --list: the hidden columns are project and path" {
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  cd "${REPO}"

  run_grove switch --list

  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_column 2)" "project"
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_column 3)" "${worktree}"
  assert_equal "$(printf '%s\n' "${lines[0]}" | awk -F'\t' '{print NF}')" 3
}

@test "switch --list: the display column is the name padded to 512 plus the project" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"

  run_grove switch --list

  local display
  display=$(printf '%s\n' "${lines[0]}" | entry_column 1)
  assert_equal "${#display}" "$((2 + 512 + 7))"
  assert [ "${display}" = "  a$(printf '%*s' 511 '')project" ]
}

@test "switch --list: strips the default prefix" {
  make_worktree "${REPO}" grove-fix-login > /dev/null
  cd "${REPO}"

  run_grove switch --list

  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "fix-login"
}

@test "switch --list: keeps names that do not have the prefix" {
  make_worktree "${REPO}" feature > /dev/null
  cd "${REPO}"

  run_grove switch --list

  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "feature"
}

@test "switch --list: only strips the prefix at the start of the name" {
  make_worktree "${REPO}" my-grove-x > /dev/null
  cd "${REPO}"

  run_grove switch --list

  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "my-grove-x"
}

@test "switch --list: honors a custom GROVE_PREFIX" {
  make_worktree "${REPO}" task-a > /dev/null
  make_worktree "${REPO}" grove-b > /dev/null
  cd "${REPO}"

  GROVE_PREFIX="task-" run_grove switch --list

  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "grove-b"
  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_name)" "a"
}

@test "switch --list: an empty GROVE_PREFIX strips nothing" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"

  GROVE_PREFIX="" run_grove switch --list

  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "grove-a"
}

@test "switch --list: prints no project headers when scoped to a project" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"

  run_grove switch --list

  refute_output --partial $'\033'
}

@test "switch --list: works from inside a linked worktree" {
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  make_worktree "${REPO}" grove-b > /dev/null
  cd "${worktree}"

  run_grove switch --list

  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_column 2)" "project"
}

@test "switch --list: works from a subdirectory of a linked worktree" {
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  mkdir -p "${worktree}/sub"
  cd "${worktree}/sub"

  run_grove switch --list

  assert_equal "${#lines[@]}" 1
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_column 2)" "project"
}

@test "switch --list: works from a subdirectory of the main repository" {
  make_worktree "${REPO}" grove-a > /dev/null
  mkdir -p "${REPO}/sub"
  cd "${REPO}/sub"

  run_grove switch --list

  assert_equal "${#lines[@]}" 1
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_column 2)" "project"
}

@test "switch --list: a project reached through a symlink does not list its main worktree" {
  make_worktree "${REPO}" grove-a > /dev/null
  ln -s "${TEST_TMP}/src" "${TEST_TMP}/link"
  cd "${TEST_TMP}/link/project"

  run_grove switch --list

  assert_equal "${#lines[@]}" 1
}

@test "switch --list: lists worktrees outside the worktrees directory too" {
  local -r custom="${TEST_TMP}/elsewhere/custom"
  git -C "${REPO}" worktree add --quiet "${custom}" -b feature
  cd "${REPO}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 1
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_column 3)" "${custom}"
}

@test "switch --list: inside a project lists a locked worktree" {
  local worktree
  worktree=$(make_worktree "${REPO}" grove-locked)
  git -C "${REPO}" worktree lock "${worktree}"
  cd "${REPO}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 1
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "locked"
}

@test "switch --list: inside a project strips a slash prefix from nested worktrees" {
  git -C "${REPO}" worktree add --quiet "${GROVE_WORKTREES}/feat/thing" -b feat/thing
  cd "${REPO}"

  GROVE_PREFIX="feat/" run_grove switch --list

  assert_equal "${#lines[@]}" 1
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "thing"
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_column 3)" "${GROVE_WORKTREES}/feat/thing"
}

@test "switch --list: inside a project skips stale entries whose directory is gone" {
  local gone
  gone=$(make_worktree "${REPO}" grove-gone)
  make_worktree "${REPO}" grove-here > /dev/null
  rm -rf "${gone}"
  cd "${REPO}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 1
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "here"
}

@test "switch --list: inside a project skips detached worktrees" {
  local detached
  detached=$(make_worktree "${REPO}" grove-detached)
  make_worktree "${REPO}" grove-here > /dev/null
  git -C "${detached}" checkout --quiet --detach
  cd "${REPO}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 1
  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "here"
}

@test "switch --list: prints nothing when the project has no worktrees" {
  cd "${REPO}"

  run_grove switch --list

  assert_success
  assert_output ""
}

@test "switch --list: sorts a project's worktrees by branch name" {
  make_worktree "${REPO}" grove-c > /dev/null
  make_worktree "${REPO}" grove-a > /dev/null
  make_worktree "${REPO}" grove-b > /dev/null
  cd "${REPO}"

  run_grove switch --list

  assert_equal "$(printf '%s\n' "${lines[0]}" | entry_name)" "a"
  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_name)" "b"
  assert_equal "$(printf '%s\n' "${lines[2]}" | entry_name)" "c"
}

# --- --list outside a project ------------------------------------------------

@test "switch --list: outside a repository scans the worktrees directory" {
  local alpha beta
  alpha=$(make_repo alpha)
  beta=$(make_repo beta)
  make_worktree "${alpha}" grove-one > /dev/null
  make_worktree "${beta}" grove-two > /dev/null
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_success
  assert_equal "${#lines[@]}" 4
  assert_equal "${lines[0]}" $'\033[1;2malpha\033[0m'
  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_name)" "one"
  assert_equal "${lines[2]}" $'\033[1;2mbeta\033[0m'
  assert_equal "$(printf '%s\n' "${lines[3]}" | entry_name)" "two"
}

@test "switch --list: outside a repository the hidden columns carry project and path" {
  local alpha worktree
  alpha=$(make_repo alpha)
  worktree=$(make_worktree "${alpha}" grove-one)
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_column 2)" "alpha"
  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_column 3)" "${worktree}"
}

@test "switch --list: header rows have no hidden columns" {
  local alpha
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "$(printf '%s\n' "${lines[0]}" | awk -F'\t' '{print NF}')" 1
}

@test "switch --list: outside a repository each project appears once" {
  local alpha
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  make_worktree "${alpha}" grove-two > /dev/null
  make_worktree "${alpha}" grove-three > /dev/null
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 4
  assert_equal "$(printf '%s\n' "${output}" | grep -c $'\033\\[1;2malpha')" 1
}

@test "switch --list: outside a repository projects are grouped alphabetically" {
  local zulu alpha
  zulu=$(make_repo zulu)
  alpha=$(make_repo alpha)
  make_worktree "${zulu}" grove-z1 > /dev/null
  make_worktree "${alpha}" grove-a1 > /dev/null
  make_worktree "${zulu}" grove-z2 > /dev/null
  make_worktree "${alpha}" grove-a2 > /dev/null
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${lines[0]}" $'\033[1;2malpha\033[0m'
  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_name)" "a1"
  assert_equal "$(printf '%s\n' "${lines[2]}" | entry_name)" "a2"
  assert_equal "${lines[3]}" $'\033[1;2mzulu\033[0m'
  assert_equal "$(printf '%s\n' "${lines[4]}" | entry_name)" "z1"
  assert_equal "$(printf '%s\n' "${lines[5]}" | entry_name)" "z2"
}

@test "switch --list: outside a repository also lists a project's worktrees stored elsewhere" {
  local alpha
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  git -C "${alpha}" worktree add --quiet "${TEST_TMP}/elsewhere" -b grove-other
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 3
}

@test "switch --list: outside a repository keeps project names and paths with spaces intact" {
  local project worktree
  project=$(make_repo "my project")
  worktree=$(make_worktree "${project}" grove-a "${GROVE_WORKTREES}/with space")
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[0]}" $'\033[1;2mmy project\033[0m'
  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_column 2)" "my project"
  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_column 3)" "${worktree}"
}

@test "switch --list: errors when the worktrees directory is missing outside a repository" {
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_failure 1
  assert_stderr "Error: ${GROVE_WORKTREES} does not exist."
}

@test "switch --list: inside tmux the missing directory error is shown in tmux" {
  enter_tmux
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: ${GROVE_WORKTREES} does not exist.'"
}

@test "switch --list: an empty worktrees directory prints nothing" {
  mkdir -p "${GROVE_WORKTREES}"
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_success
  assert_output ""
}

@test "switch --list: skips directories that are not worktrees" {
  local alpha
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  mkdir -p "${GROVE_WORKTREES}/not-a-worktree"
  printf 'x' > "${GROVE_WORKTREES}/a-file"
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 2
}

@test "switch --list: outside a repository skips stale entries whose directory is gone" {
  local alpha gone
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  gone=$(make_worktree "${alpha}" grove-gone)
  rm -rf "${gone}"
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 2
  assert_equal "$(printf '%s\n' "${lines[1]}" | entry_name)" "one"
}

@test "switch --list: skips worktrees whose main repository is gone" {
  local alpha beta
  alpha=$(make_repo alpha)
  beta=$(make_repo beta)
  make_worktree "${alpha}" grove-one > /dev/null
  make_worktree "${beta}" grove-two > /dev/null
  rm -rf "${alpha}"
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[0]}" $'\033[1;2mbeta\033[0m'
}

@test "switch --list: outside a repository skips detached worktrees" {
  local alpha detached
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  detached=$(make_worktree "${alpha}" grove-detached)
  git -C "${detached}" checkout --quiet --detach
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 2
}

@test "switch --list: honors GROVE_WORKTREES" {
  export GROVE_WORKTREES="${TEST_TMP}/custom"
  local alpha
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 2
}

@test "switch --list: ignores the default location when GROVE_WORKTREES is set" {
  local alpha
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  export GROVE_WORKTREES="${TEST_TMP}/custom"
  mkdir -p "${GROVE_WORKTREES}"
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_output ""
}

@test "switch --list: honors GROVE_ROOT when GROVE_WORKTREES is unset" {
  unset GROVE_WORKTREES
  export GROVE_ROOT="${TEST_TMP}/other-root"
  local alpha
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one "${GROVE_ROOT}/worktrees/grove-one" > /dev/null
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 2
}

@test "switch --list: GROVE_WORKTREES wins over GROVE_ROOT" {
  export GROVE_ROOT="${TEST_TMP}/ignored-root"
  mkdir -p "${GROVE_ROOT}/worktrees"
  local alpha
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_equal "${#lines[@]}" 2
}

@test "switch --list: with neither variable set the directory is HOME/Sites/worktrees" {
  unset GROVE_ROOT GROVE_WORKTREES
  cd "${TEST_TMP}"

  run_grove switch --list

  assert_failure 1
  assert_stderr "Error: ${HOME}/Sites/worktrees does not exist."
}

# --- The picker --------------------------------------------------------------

@test "switch: errors when there are no worktrees in the project" {
  cd "${REPO}"

  run_grove switch

  assert_failure 1
  assert_stderr "Error: No worktrees found in ${GROVE_WORKTREES}."
  assert_equal "$(fzf_call_count)" 0
}

@test "switch: the no-worktrees error names GROVE_ROOT's directory when only it is set" {
  unset GROVE_WORKTREES
  export GROVE_ROOT="${TEST_TMP}/other-root"
  cd "${REPO}"

  run_grove switch

  assert_failure 1
  assert_stderr "Error: No worktrees found in ${GROVE_ROOT}/worktrees."
}

@test "switch: inside tmux the no-worktrees error is shown in tmux" {
  enter_tmux
  cd "${REPO}"

  run_grove switch

  assert_failure 1
  assert_tmux_call_exact "display-message -d 2000 'grove: No worktrees found in ${GROVE_WORKTREES}.'"
}

@test "switch: errors when the worktrees directory is missing outside a repository" {
  cd "${TEST_TMP}"

  run_grove switch

  assert_failure 1
  assert_stderr "Error: ${GROVE_WORKTREES} does not exist."
}

@test "switch: exits 0 when fzf is cancelled" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"
  fzf_exit_code 130

  run_grove switch

  assert_success
  assert_output ""
  refute_any_tmux_call
}

@test "switch: exits 0 when the selection is empty" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"

  run_grove switch

  assert_success
  refute_any_tmux_call
}

@test "switch: exits 0 when a project header row is selected" {
  local alpha
  alpha=$(make_repo alpha)
  make_worktree "${alpha}" grove-one > /dev/null
  cd "${TEST_TMP}"
  fzf_select $'\033[1;2malpha\033[0m\n'

  run_grove switch

  assert_success
  refute_any_tmux_call
}

@test "switch: passes the entries to fzf on stdin" {
  make_worktree "${REPO}" grove-a > /dev/null
  make_worktree "${REPO}" grove-b > /dev/null
  cd "${REPO}"

  run_grove switch --list
  local -r expected="${output}"

  run_grove switch

  assert_equal "$(fzf_stdin)" "${expected}"
}

@test "switch: passes the expected options and bindings to fzf" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"

  run_grove switch

  assert_fzf_arg "--prompt=worktree> "
  assert_fzf_arg "--height=50%"
  assert_fzf_arg "--reverse"
  assert_fzf_arg "--ansi"
  assert_fzf_arg $'--delimiter=\t'
  assert_fzf_arg "--with-nth=1"
  assert_fzf_arg "--no-hscroll"
  assert_fzf_arg "--ellipsis"
  assert_fzf_arg ""
  assert_fzf_arg $'--footer=Enter: Open  Ctrl-b: Rename  Ctrl-d: Delete'
  assert_fzf_arg '--bind'
  assert_fzf_arg 'enter:transform:[[ -n {2} ]] && echo accept'
  assert_fzf_arg 'ctrl-b:execute(grove _rename-prompt {3})+reload(grove switch --list)'
  assert_fzf_arg 'ctrl-d:execute(grove _delete-confirm {3})+reload(grove switch --list)'
}

@test "switch: removes its temporary file when it exits normally" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"
  mkdir "${TEST_TMP}/tmpdir"

  TMPDIR="${TEST_TMP}/tmpdir" run_grove switch

  assert_success
  assert_equal "$(ls -A "${TEST_TMP}/tmpdir")" ""
}

@test "switch: removes its temporary file when it errors" {
  cd "${REPO}"
  mkdir "${TEST_TMP}/tmpdir"

  TMPDIR="${TEST_TMP}/tmpdir" run_grove switch

  assert_failure 1
  assert_equal "$(ls -A "${TEST_TMP}/tmpdir")" ""
}

@test "switch: removes its temporary file after opening a worktree outside tmux" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"
  mkdir "${TEST_TMP}/tmpdir"
  select_entry a

  TMPDIR="${TEST_TMP}/tmpdir" run_grove switch

  assert_success
  assert_equal "$(ls -A "${TEST_TMP}/tmpdir")" ""
}

# --- Switching to an existing window -----------------------------------------

@test "switch: inside tmux, switches to a window that already has the worktree" {
  enter_tmux
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  cd "${REPO}"
  select_entry a
  tmux_add_pane grove 3 0 0 1 %5 "${worktree}"

  run_grove switch

  assert_success
  assert_tmux_call_exact "switch-client -t grove:3"
  refute_tmux_called "attach-session"
  refute_tmux_called "new-window"
  refute_tmux_called "new-session"
}

@test "switch: outside tmux, attaches to the window that already has the worktree" {
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  cd "${REPO}"
  select_entry a
  tmux_add_pane grove 3 0 0 1 %5 "${worktree}"

  run_grove switch

  assert_success
  assert_tmux_call_exact "attach-session -t grove:3"
  refute_tmux_called "switch-client"
  refute_tmux_called "new-window"
}

@test "switch: matches a pane in a subdirectory of the worktree" {
  enter_tmux
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  cd "${REPO}"
  select_entry a
  tmux_add_pane grove 4 0 0 1 %5 "${worktree}/sub/dir"

  run_grove switch

  assert_tmux_call_exact "switch-client -t grove:4"
}

@test "switch: searches the panes of every session" {
  enter_tmux
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  cd "${REPO}"
  select_entry a
  tmux_add_pane other 9 0 0 1 %5 "${worktree}"

  run_grove switch

  assert_tmux_call_exact "switch-client -t other:9"
  assert_tmux_called "list-panes -a"
}

@test "switch: does not match a pane whose path only shares a prefix" {
  enter_tmux
  local worktree sibling
  worktree=$(make_worktree "${REPO}" grove-a)
  sibling=$(make_worktree "${REPO}" grove-a-two)
  cd "${REPO}"
  select_entry a
  tmux_add_pane grove 5 0 0 1 %5 "${sibling}"
  tmux_add_pane grove 6 0 0 1 %6 "${sibling}/sub"

  run_grove switch

  refute_tmux_called "switch-client"
  assert_tmux_called "new-session"
}

@test "switch: uses the first matching window" {
  enter_tmux
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  cd "${REPO}"
  select_entry a
  tmux_add_pane grove 3 0 0 1 %5 "${worktree}"
  tmux_add_pane grove 8 0 0 1 %6 "${worktree}"

  run_grove switch

  assert_tmux_call_exact "switch-client -t grove:3"
}

# --- Opening a worktree ------------------------------------------------------

@test "switch: opens a new session with --continue when no window exists" {
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  cd "${REPO}"
  select_entry a

  run_grove switch

  assert_success
  assert_tmux_call_exact "has-session -t project"
  assert_tmux_call_exact "new-session -d -s project -n grove-a -c ${worktree} -x 120 -y 40 -P -F #{pane_id}"
  assert_tmux_call_exact "send-keys -t %1 'claude --continue' Enter"
  assert_tmux_call_exact "send-keys -t %2 'grove file-watch' Enter"
}

@test "switch: adds a window when the session already exists" {
  enter_tmux
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  cd "${REPO}"
  select_entry a
  tmux_fixture_session

  run_grove switch

  assert_success
  assert_tmux_call_exact "new-window -a -t project -n grove-a -c ${worktree} -P -F #{pane_id}"
  refute_tmux_called "new-session"
}

@test "switch: GROVE_AGENT is used with --continue" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"
  select_entry a

  GROVE_AGENT=codex run_grove switch

  assert_tmux_call_exact "send-keys -t %1 'codex --continue' Enter"
}

@test "switch: does not run setup.sh for an existing worktree" {
  commit_grove_script "${REPO}" setup.sh 755
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"
  select_entry a

  run_grove switch

  assert_success
  refute_tmux_called "setup.sh"
  refute_tmux_called "display-message -d 3000"
}

@test "switch: outside tmux, attaches to the new session" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"
  select_entry a

  run_grove switch

  assert_tmux_call_exact "attach-session -t project"
}

@test "switch: inside tmux, does not attach" {
  enter_tmux
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"
  select_entry a

  run_grove switch

  refute_tmux_called "attach-session"
}

@test "switch: outside tmux, adds a window to an existing session and attaches to it" {
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a)
  cd "${REPO}"
  select_entry a
  tmux_fixture_session

  run_grove switch

  assert_success
  assert_tmux_called "new-window"
  assert_tmux_called "-n grove-a -c ${worktree} -P"
  assert_tmux_called "attach-session"
  refute_tmux_called "new-session"
}

@test "switch: reuses the session with exactly the project's name" {
  make_worktree "${REPO}" grove-a > /dev/null
  cd "${REPO}"
  select_entry a
  tmux_add_session "project"
  tmux_add_session "project-docs"

  run_grove switch

  assert_success
  assert_tmux_called "new-window"
  refute_tmux_called "new-session"
}

@test "switch: the session name comes from the project selected outside a repository" {
  local alpha
  alpha=$(make_repo "my.alpha:one")
  make_worktree "${alpha}" grove-a > /dev/null
  cd "${TEST_TMP}"
  select_entry a

  run_grove switch

  assert_tmux_called "has-session -t my_alpha_one"
  assert_tmux_called "new-session -d -s my_alpha_one -n grove-a"
}

@test "switch: the window name is the worktree directory name" {
  local worktree
  worktree=$(make_worktree "${REPO}" grove-a "${TEST_TMP}/elsewhere-dir")
  cd "${REPO}"
  select_entry a

  run_grove switch

  assert_tmux_called "-n elsewhere-dir -c ${worktree}"
}

@test "switch: opens the selected worktree when several exist" {
  make_worktree "${REPO}" grove-a > /dev/null
  local second
  second=$(make_worktree "${REPO}" grove-b)
  cd "${REPO}"
  select_entry b

  run_grove switch

  assert_tmux_called "-n grove-b -c ${second}"
  refute_tmux_called "-n grove-a"
}
