#!/usr/bin/env bash
#
# Shared setup and helpers for the grove test suite. Load it at the top of a
# .bats file and call common_setup from setup():
#
#   load 'test_helper/common'
#
#   setup() {
#     common_setup
#   }

set -euo pipefail

bats_require_minimum_version 1.5.0

# The load.bash files of bats-support and bats-assert run dirname in a subshell
# for every file they source, which costs about 15ms per test. Their src/ files
# only define functions, so source them directly. BATS_SAVED_PATH is the one
# variable bats-support/load.bash sets, for bats versions before 1.10.
BATS_SAVED_PATH="${BATS_SAVED_PATH-${PATH}}"
for helper_file in "${BATS_TEST_DIRNAME}"/test_helper/bats-{support,assert}/src/*.bash; do
  source "${helper_file}"
done
unset helper_file

# BATS_TEST_DIRNAME is already an absolute path.
readonly GROVE_BIN="${BATS_TEST_DIRNAME%/*}/bin/grove"
readonly STUBS_DIR="${BATS_TEST_DIRNAME}/stubs"

# Build a sandbox for one test. Nothing outside BATS_TEST_TMPDIR is touched, and
# tmux, fzf, less, sleep and tput are replaced by the stubs in test/stubs.
common_setup() {
  TEST_TMP=$(cd "${BATS_TEST_TMPDIR}" && pwd -P)
  export TEST_TMP

  export HOME="${TEST_TMP}/home"
  export GROVE_ROOT="${TEST_TMP}/root"
  export GROVE_WORKTREES="${GROVE_ROOT}/worktrees"
  export LC_ALL=C

  export_git_environment "${TEST_TMP}"

  unset TMUX TMUX_PANE GROVE_AGENT GROVE_PREFIX
  unset LESS_STUB_LOG SLEEP_STUB_LOG TPUT_STUB_COLS TPUT_STUB_LINES TPUT_STUB_FAIL

  export TMUX_STUB_DIR="${TEST_TMP}/stub/tmux"
  export FZF_STUB_DIR="${TEST_TMP}/stub/fzf"
  mkdir -p "${HOME}" "${TEST_TMP}/src" "${TMUX_STUB_DIR}" "${FZF_STUB_DIR}"

  # The stubs shadow tmux, fzf, less, sleep and tput for every process the test
  # starts, including bats helpers, because tests call grove in several ways.
  export PATH="${STUBS_DIR}:${PATH}"
}

# Point git at a global config file in the given directory, ignore the system
# one, and fix the identity and dates so commits are the same in every run.
# Settings go in through the environment, which avoids spawning git once per
# setting. Usage: export_git_environment <directory>
export_git_environment() {
  local -r sandbox_dir="$1"

  export GIT_CONFIG_GLOBAL="${sandbox_dir}/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_TERMINAL_PROMPT=0
  export GIT_AUTHOR_NAME="Grove Test"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Grove Test"
  export GIT_COMMITTER_EMAIL="test@example.com"
  export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
  export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

  export GIT_CONFIG_COUNT=3
  export GIT_CONFIG_KEY_0="init.defaultBranch" GIT_CONFIG_VALUE_0="main"
  export GIT_CONFIG_KEY_1="commit.gpgsign" GIT_CONFIG_VALUE_1="false"
  export GIT_CONFIG_KEY_2="advice.detachedHead" GIT_CONFIG_VALUE_2="false"

  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX
}

# Fail unless HOME and every grove or git location that is set point inside the
# test's temporary directory. An unset GROVE_ROOT or GROVE_WORKTREES is fine
# because grove then falls back to "${HOME}/Sites", and HOME is checked. Called
# before every way of running grove, so a test body that changes these variables
# cannot reach the real home directory.
assert_sandboxed() {
  local name value
  for name in HOME GROVE_ROOT GROVE_WORKTREES GIT_CONFIG_GLOBAL; do
    if [[ -z "${!name+x}" ]]; then
      continue
    fi

    value="${!name}"
    if [[ "${value}" != "${TEST_TMP}" && "${value}" != "${TEST_TMP}"/* ]]; then
      fail "refusing to run: ${name}=${value} is outside ${TEST_TMP}"
      return 1
    fi

    if [[ "${value}" == */../* || "${value}" == */.. ]]; then
      fail "refusing to run: ${name}=${value} contains a parent directory reference"
      return 1
    fi
  done

  if [[ -z "${HOME:-}" ]]; then
    fail "refusing to run: HOME is unset"
    return 1
  fi
}

# --- Running grove ---------------------------------------------------------

# Run grove with stdout in $output and stderr in $stderr.
run_grove() {
  assert_sandboxed
  run --separate-stderr "${GROVE_BIN}" "$@"
}

# Run grove under timeout, for commands that never exit on their own.
run_grove_timeout() {
  local -r seconds="$1"
  shift

  assert_sandboxed
  run --separate-stderr timeout "${seconds}" "${GROVE_BIN}" "$@"
}

# Run a command inside a pseudo terminal so grove can read from /dev/tty. The
# first argument is the text typed at the prompt. Output (including the prompt)
# ends up in $output.
#
# The text is typed through a FIFO that stays open until script(1) exits. When
# its standard input ends first, script waits in steps of 250ms, up to 2s, for
# the program to read everything that was typed.
run_grove_with_tty() {
  local -r typed="$1"
  shift

  assert_sandboxed

  local command_line
  command_line=$(printf '%q ' "${GROVE_BIN}" "$@")

  local -r input_fifo="${TEST_TMP}/tty-input"
  rm -f "${input_fifo}"
  mkfifo "${input_fifo}"

  run bash -c 'script -qec "$2" /dev/null <"$3" & exec 3>"$3"; printf "%s\n" "$1" >&3; wait "$!"' \
    _ "${typed}" "${command_line}" "${input_fifo}"
}

# Pretend to be inside a tmux client.
enter_tmux() {
  export TMUX="${TEST_TMP}/tmux-socket,1,0"
}

strip_ansi() {
  sed $'s/\x1b\\[[0-9;]*m//g'
}

# --- Git fixtures ----------------------------------------------------------

# Create a repository with one commit at the path. setup_suite builds one with
# this, and make_repo copies it.
build_repo_template() {
  local -r repo_path="$1"

  mkdir -p "${repo_path}"
  git -C "${repo_path}" init --quiet
  printf 'hello\n' > "${repo_path}/README.md"
  git -C "${repo_path}" add README.md
  git -C "${repo_path}" commit --quiet -m "Initial commit."
}

# Create a repository with one commit and print its path. Copying the template
# from setup_suite is several times faster than running git init, add and
# commit for every test.
make_repo() {
  local -r name="$1"
  local -r repo_path="${TEST_TMP}/src/${name}"

  cp -a "${REPO_TEMPLATE}" "${repo_path}"

  printf '%s\n' "${repo_path}"
}

# Write a file in a repository and commit it. Usage: commit_file <repo> <file>
# [content] [message]
commit_file() {
  local -r repo_path="$1"
  local -r file_name="$2"
  local -r content="${3:-content}"
  local -r message="${4:-Add ${file_name}.}"

  mkdir -p "$(dirname "${repo_path}/${file_name}")"
  printf '%s\n' "${content}" > "${repo_path}/${file_name}"
  git -C "${repo_path}" add -- "${file_name}"
  git -C "${repo_path}" commit --quiet -m "${message}"
}

# Create a linked worktree the way grove does, and print its path. Usage:
# make_worktree <repo> <branch> [path]
make_worktree() {
  local -r repo_path="$1"
  local -r branch="$2"
  local -r worktree_path="${3:-${GROVE_WORKTREES}/${branch}}"

  git -C "${repo_path}" worktree add --quiet "${worktree_path}" -b "${branch}"

  printf '%s\n' "${worktree_path}"
}

# Register enough linked worktrees that `git worktree list --porcelain` prints
# more than 4KB, which git writes in several chunks. Usage: add_many_worktrees <repo>
add_many_worktrees() {
  local -r repo_path="$1"
  local index

  for index in $(seq 1 40); do
    git -C "${repo_path}" worktree add --quiet "${TEST_TMP}/many/worktree-number-${index}" -b "many-${index}"
  done
}

# Commit a script into a repository's .grove/ directory (so every worktree gets
# a copy). Usage: commit_grove_script <repo> <name> [mode]
commit_grove_script() {
  local -r repo_path="$1"
  local -r script_name="$2"
  local -r mode="${3:-755}"

  mkdir -p "${repo_path}/.grove"
  printf '#!/usr/bin/env bash\necho %s\n' "${script_name}" > "${repo_path}/.grove/${script_name}"
  chmod "${mode}" "${repo_path}/.grove/${script_name}"
  git -C "${repo_path}" add -- ".grove/${script_name}"
  git -C "${repo_path}" commit --quiet -m "Add ${script_name}."
}

# Create an uncommitted script in a repository's .grove/ directory.
write_grove_script() {
  local -r repo_path="$1"
  local -r script_name="$2"
  local -r mode="${3:-755}"

  mkdir -p "${repo_path}/.grove"
  printf '#!/usr/bin/env bash\necho %s\n' "${script_name}" > "${repo_path}/.grove/${script_name}"
  chmod "${mode}" "${repo_path}/.grove/${script_name}"
}

branch_exists() {
  git -C "$1" show-ref --verify --quiet "refs/heads/$2"
}

# True when the worktree list of a repository contains the path.
worktree_registered() {
  git -C "$1" worktree list --porcelain | grep -Fqx "worktree $2"
}

# --- tmux stub -------------------------------------------------------------

tmux_calls() {
  if [[ -f "${TMUX_STUB_DIR}/calls.log" ]]; then
    cat "${TMUX_STUB_DIR}/calls.log"
  fi
}

# Set a fixture value. Usage: tmux_fixture <name> <value>
tmux_fixture() {
  printf '%s\n' "$2" > "${TMUX_STUB_DIR}/$1"
}

tmux_fixture_session() {
  tmux_fixture has_session 0
}

# Describe a pane. Usage: tmux_add_pane <session> <window> <left> <top>
# <active> <id> <path>
tmux_add_pane() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "${TMUX_STUB_DIR}/panes"
}

# Add a session that exists. Once any session is added, the stub resolves the
# target of has-session like tmux does, so a name that only starts with the
# target also matches.
tmux_add_session() {
  printf '%s\n' "$1" >> "${TMUX_STUB_DIR}/sessions"
}

# Print the text typed into a pane by send-keys, one line per call, exactly as
# a shell in that pane would receive it. Usage: tmux_sent_keys <pane>
tmux_sent_keys() {
  if [[ -f "${TMUX_STUB_DIR}/keys.log" ]]; then
    awk -F'\t' -v pane="$1" '$1 == pane { sub(/^[^\t]*\t/, ""); print }' "${TMUX_STUB_DIR}/keys.log"
  fi
}

# Fail unless some tmux call contains the fragment.
assert_tmux_called() {
  local -r fragment="$1"

  if ! tmux_calls | grep -Fq -- "${fragment}"; then
    fail "$(printf 'expected a tmux call containing: %s\ntmux calls:\n%s' "${fragment}" "$(tmux_calls)")"
  fi
}

# Fail unless a tmux call equals the line exactly.
assert_tmux_call_exact() {
  local -r line="$1"

  if ! tmux_calls | grep -Fxq -- "${line}"; then
    fail "$(printf 'expected the tmux call: %s\ntmux calls:\n%s' "${line}" "$(tmux_calls)")"
  fi
}

# Fail when any tmux call contains the fragment.
refute_tmux_called() {
  local -r fragment="$1"

  if tmux_calls | grep -Fq -- "${fragment}"; then
    fail "$(printf 'expected no tmux call containing: %s\ntmux calls:\n%s' "${fragment}" "$(tmux_calls)")"
  fi
}

# Fail unless there were no tmux calls at all.
refute_any_tmux_call() {
  if [[ -n "$(tmux_calls)" ]]; then
    fail "$(printf 'expected no tmux calls, got:\n%s' "$(tmux_calls)")"
  fi
}

# Print how many tmux calls contain the fragment.
tmux_call_count() {
  tmux_calls | grep -Fc -- "$1" || true
}

# --- fzf stub --------------------------------------------------------------

# Make the stub print the given text (what the user "selected").
fzf_select() {
  printf '%s' "$1" > "${FZF_STUB_DIR}/output"
}

fzf_exit_code() {
  printf '%s\n' "$1" > "${FZF_STUB_DIR}/rc"
}

fzf_argv() {
  cat "${FZF_STUB_DIR}/argv"
}

fzf_stdin() {
  cat "${FZF_STUB_DIR}/stdin"
}

fzf_call_count() {
  if [[ -f "${FZF_STUB_DIR}/calls" ]]; then
    cat "${FZF_STUB_DIR}/calls"
  else
    echo 0
  fi
}

# Fail unless fzf received exactly this argument.
assert_fzf_arg() {
  local -r expected="$1"

  if ! fzf_argv | grep -Fxq -- "${expected}"; then
    fail "$(printf 'expected fzf argument: %s\nfzf arguments:\n%s' "${expected}" "$(fzf_argv)")"
  fi
}

# Print the action bound to a key in the recorded fzf arguments, without the
# "<key>:" in front of it. Usage: fzf_binding <key>
fzf_binding() {
  local -r key="$1"

  local line
  while IFS= read -r line; do
    if [[ "${line}" == "${key}:"* ]]; then
      printf '%s\n' "${line#"${key}:"}"
      return 0
    fi
  done < <(fzf_argv)

  fail "fzf received no binding for ${key}"
}

# Quote a value the way fzf quotes the {n} placeholders of a binding: as one
# shell word wrapped in single quotes.
fzf_quote() {
  local -r value="$1"

  printf "'%s'" "${value//\'/\'\\\'\'}"
}

# Replace the {2} and {3} placeholders in the command of a binding the way fzf
# does and print the result. Usage: fzf_expand <command> <field-2> [field-3]
fzf_expand() {
  local expanded="$1"

  local field_three field_two
  field_two=$(fzf_quote "$2")
  field_three=$(fzf_quote "${3:-}")

  expanded="${expanded//\{2\}/"${field_two}"}"
  expanded="${expanded//\{3\}/"${field_three}"}"

  printf '%s\n' "${expanded}"
}

# Carry out an fzf action for a row the way fzf does, and leave the result of the
# last command in $output and $status. A "transform:" action runs a shell command
# whose output is the next action. An "execute(...)" or "execute-silent(...)"
# action runs a shell command, and anything chained after it, like
# "+reload(...)", is left alone. The placeholders {2} and {3} are replaced by the
# quoted field values in every command that is run, as fzf does.
# Usage: run_fzf_action <action> <field-2> [field-3]
run_fzf_action() {
  local action="$1"
  local -r field_two="$2"
  local -r field_three="${3:-}"

  local command
  case "${action}" in
    transform:*)
      command=$(fzf_expand "${action#transform:}" "${field_two}" "${field_three}")
      run bash -c "${command}"

      # A transform that prints nothing, like on a header row, ends here.
      if [[ -n "${output}" ]]; then
        run_fzf_action "${output}" "${field_two}" "${field_three}"
      fi
      ;;
    execute\(*|execute-silent\(*)
      command="${action%%+reload(*}"
      command="${command#*\(}"
      command="${command%)}"
      command=$(fzf_expand "${command}" "${field_two}" "${field_three}")
      run bash -c "${command}"
      ;;
    *)
      fail "cannot carry out the fzf action: ${action}"
      ;;
  esac
}

# --- Switcher entries ------------------------------------------------------

# Print one column of a switcher entry line (read from stdin). Columns are
# 1 (display), 2 (project) and 3 (path).
entry_column() {
  cut -f"$1"
}

# Print the display name of an entry line (read from stdin). Branch names never
# contain spaces, so the name is the first word of the display column.
entry_name() {
  cut -f1 | sed 's/^  //; s/ .*$//'
}
