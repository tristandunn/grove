#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  REPO=$(make_repo project)
  cd "${REPO}"
}

readonly ESC=$'\033'

# Print the row for a file in a section ("unstaged" or "staged") from $output.
row() {
  printf '%s\n' "${output}" | awk -F'\t' -v file="$1" -v section="$2" '$2 == file && $3 == section'
}

# Print just the display column of a row.
display() {
  row "$1" "$2" | cut -f1
}

# --- Layout of --status ------------------------------------------------------

@test "file-watch --status: prints nothing for a clean tree" {
  run_grove file-watch --status

  assert_success
  assert_output ""
}

@test "file-watch --status: header rows end with a tab and carry no filename" {
  printf 'changed\n' > README.md
  printf 'staged\n' > staged.txt
  git add staged.txt

  run_grove file-watch --status

  assert_success
  assert_equal "${lines[0]}" "${ESC}[1;2mUnstaged${ESC}[0m"$'\t'
  assert_equal "$(printf '%s\n' "${lines[0]}" | awk -F'\t' '{print NF ":" $2}')" "2:"
  assert_equal "$(printf '%s\n' "${output}" | grep -c $'\t''$')" 2
}

@test "file-watch --status: only the sections that have files get a header" {
  printf 'staged\n' > staged.txt
  git add staged.txt

  run_grove file-watch --status

  refute_output --partial "Unstaged"
  assert_output --partial "${ESC}[1;2mStaged${ESC}[0m"$'\t'
}

@test "file-watch --status: data rows have the display text, filename and section" {
  printf 'changed\n' > README.md

  run_grove file-watch --status

  assert_equal "$(printf '%s\n' "${lines[1]}" | awk -F'\t' '{print NF}')" 3
  assert_equal "$(printf '%s\n' "${lines[1]}" | cut -f2)" "README.md"
  assert_equal "$(printf '%s\n' "${lines[1]}" | cut -f3)" "unstaged"
}

@test "file-watch --status: unstaged rows come before staged rows" {
  printf 'changed\n' > README.md
  printf 'staged\n' > staged.txt
  git add staged.txt

  run_grove file-watch --status

  assert_equal "$(printf '%s\n' "${lines[0]}" | strip_ansi)" "Unstaged"$'\t'
  assert_equal "$(printf '%s\n' "${lines[2]}" | strip_ansi)" "Staged"$'\t'
}

# --- Unstaged ------------------------------------------------------------------

@test "file-watch --status: lists a modified file with green additions and red removals" {
  printf 'a\nb\nc\n' > data.txt
  git add data.txt && git commit --quiet -m "Add data."
  printf 'a\nB\nc\nd\n' > data.txt

  run_grove file-watch --status

  assert_equal "$(display data.txt unstaged)" "   M  data.txt  ${ESC}[32m+2${ESC}[0m ${ESC}[31m-1${ESC}[0m"
  assert_equal "$(row data.txt unstaged | cut -f3)" "unstaged"
}

@test "file-watch --status: a file with only additions shows only a green count" {
  printf 'more\n' >> README.md

  run_grove file-watch --status

  assert_equal "$(display README.md unstaged)" "   M  README.md  ${ESC}[32m+1${ESC}[0m"
}

@test "file-watch --status: a file with only removals shows only a red count" {
  printf 'a\nb\n' > data.txt
  git add data.txt && git commit --quiet -m "Add data."
  printf 'a\n' > data.txt

  run_grove file-watch --status

  assert_equal "$(display data.txt unstaged)" "   M  data.txt  ${ESC}[31m-1${ESC}[0m"
}

@test "file-watch --status: an unstaged deletion shows the removed lines" {
  rm README.md

  run_grove file-watch --status

  assert_equal "$(display README.md unstaged)" "   D  README.md  ${ESC}[31m-1${ESC}[0m"
}

@test "file-watch --status: an untracked file has no counts" {
  printf 'new\n' > untracked.txt

  run_grove file-watch --status

  assert_equal "$(display untracked.txt unstaged)" "  ??  untracked.txt"
}

@test "file-watch --status: untracked files inside new directories are listed individually" {
  mkdir -p newdir/sub
  printf 'one\n' > newdir/one.txt
  printf 'two\n' > newdir/sub/two.txt

  run_grove file-watch --status

  assert [ -n "$(row newdir/one.txt unstaged)" ]
  assert [ -n "$(row newdir/sub/two.txt unstaged)" ]
  assert [ -z "$(row newdir/ unstaged)" ]
  assert [ -z "$(row newdir unstaged)" ]
}

@test "file-watch --status: a modified binary file shows no counts" {
  printf '\0\1\2' > data.bin
  git add data.bin && git commit --quiet -m "Add binary."
  printf '\0\3\4\5' > data.bin

  run_grove file-watch --status

  assert_equal "$(display data.bin unstaged)" "   M  data.bin"
  refute_output --partial "-${ESC}"
}

@test "file-watch --status: pads names so the counts line up" {
  printf 'a\n' > a.txt
  printf 'a\n' > much-longer-name.txt
  git add . && git commit --quiet -m "Add files."
  printf 'b\n' >> a.txt
  printf 'b\n' >> much-longer-name.txt

  run_grove file-watch --status

  local short long
  short=$(display a.txt unstaged | strip_ansi | awk '{print index($0, "+1")}')
  long=$(display much-longer-name.txt unstaged | strip_ansi | awk '{print index($0, "+1")}')
  assert_equal "${short}" "${long}"
  assert [ "${short}" -gt 0 ]
}

# --- Staged --------------------------------------------------------------------

@test "file-watch --status: a staged new file is dimmed with a green count" {
  printf 'a\nb\n' > added.txt
  git add added.txt

  run_grove file-watch --status

  assert_equal "$(display added.txt staged)" "  ${ESC}[90mA ${ESC}[0m  added.txt  ${ESC}[32m+2${ESC}[0m"
  assert_equal "$(row added.txt staged | cut -f3)" "staged"
}

@test "file-watch --status: a staged modification shows both counts" {
  printf 'hello\nworld\n' > README.md
  git add README.md

  run_grove file-watch --status

  assert_equal "$(display README.md staged)" "  ${ESC}[90mM ${ESC}[0m  README.md  ${ESC}[32m+1${ESC}[0m"
  assert [ -z "$(row README.md unstaged)" ]
}

@test "file-watch --status: a staged deletion shows the removed lines" {
  git rm --quiet README.md

  run_grove file-watch --status

  assert_equal "$(display README.md staged)" "  ${ESC}[90mD ${ESC}[0m  README.md  ${ESC}[31m-1${ESC}[0m"
}

@test "file-watch --status: a staged binary file shows no counts" {
  printf '\0\1\2' > data.bin
  git add data.bin

  run_grove file-watch --status

  assert_equal "$(display data.bin staged)" "  ${ESC}[90mA ${ESC}[0m  data.bin"
}

@test "file-watch --status: a rename appears as a deletion and an addition" {
  git mv README.md MOVED.md

  run_grove file-watch --status

  assert_equal "$(display README.md staged)" "  ${ESC}[90mD ${ESC}[0m  README.md  ${ESC}[31m-1${ESC}[0m"
  assert_equal "$(display MOVED.md staged)" "  ${ESC}[90mA ${ESC}[0m  MOVED.md   ${ESC}[32m+1${ESC}[0m"
}

@test "file-watch --status: lists staged files in a repository with no commits" {
  local fresh="${TEST_TMP}/fresh"
  git init --quiet "${fresh}"
  cd "${fresh}"
  printf 'x\n' > first.txt
  git add first.txt

  run_grove file-watch --status

  assert_success
  assert_equal "$(display first.txt staged)" "  ${ESC}[90mA ${ESC}[0m  first.txt  ${ESC}[32m+1${ESC}[0m"
}

# --- Both staged and unstaged ----------------------------------------------------

@test "file-watch --status: a file with staged and unstaged changes appears in both sections" {
  printf 'hello\nworld\n' > README.md
  git add README.md
  printf 'hello\nworld\n!\n' > README.md

  run_grove file-watch --status

  assert [ -n "$(row README.md unstaged)" ]
  assert [ -n "$(row README.md staged)" ]
}

@test "file-watch --status: a file with staged and unstaged changes lists each section's own counts" {
  printf 'hello\nworld\n' > README.md
  git add README.md
  printf 'hello\nworld\n!\n' > README.md

  run_grove file-watch --status

  assert_equal "$(display README.md unstaged)" "  MM  README.md  ${ESC}[32m+1${ESC}[0m"
  assert_equal "$(display README.md staged)" "  ${ESC}[90mMM${ESC}[0m  README.md  ${ESC}[32m+1${ESC}[0m"
}

# --- Awkward filenames -----------------------------------------------------------

@test "file-watch --status: preserves names with spaces" {
  printf 'x\n' > "with space.txt"

  run_grove file-watch --status

  assert_equal "$(row "with space.txt" unstaged | cut -f2)" "with space.txt"
}

@test "file-watch --status: preserves names with quotes" {
  printf 'x\n' > "it's \"quoted\".txt"

  run_grove file-watch --status

  assert_equal "$(row "it's \"quoted\".txt" unstaged | cut -f2)" "it's \"quoted\".txt"
}

@test "file-watch --status: preserves non-ASCII names unquoted" {
  printf 'x\n' > "café 日本.txt"

  run_grove file-watch --status

  assert_equal "$(row "café 日本.txt" unstaged | cut -f2)" "café 日本.txt"
}

@test "file-watch --status: shows counts for tracked files with awkward names" {
  printf 'one\n' > "sp ace's.txt"
  git add . && git commit --quiet -m "Add awkward name."
  printf 'two\n' >> "sp ace's.txt"

  run_grove file-watch --status

  assert_equal "$(display "sp ace's.txt" unstaged | strip_ansi)" "   M  sp ace's.txt  +1"
}

@test "file-watch --status: shows counts for tracked files with non-ASCII names" {
  printf 'one\n' > "naïve.txt"
  git add . && git commit --quiet -m "Add non-ASCII name."
  printf 'two\n' >> "naïve.txt"

  run_grove file-watch --status

  assert_equal "$(display "naïve.txt" unstaged | strip_ansi)" "   M  naïve.txt  +1"
}

@test "file-watch --status: names that look like section markers are ordinary files" {
  printf 'x\n' > unstaged
  printf 'x\n' > staged
  printf 'x\n' > status

  run_grove file-watch --status

  assert [ -n "$(row unstaged unstaged)" ]
  assert [ -n "$(row staged unstaged)" ]
  assert [ -n "$(row status unstaged)" ]
}

# --- Outside a repository / subdirectories --------------------------------------

@test "file-watch --status: outside a repository fails with git's error" {
  # Oddity: only the interactive mode checks for a repository first.
  cd "${TEST_TMP}"

  run_grove file-watch --status

  assert_failure
  assert_stderr --partial "not a git repository"
}

@test "file-watch --status: from a subdirectory, names and counts are relative to the repository root" {
  mkdir sub
  printf 'one\n' > sub/file.txt
  git add . && git commit --quiet -m "Add sub."
  printf 'two\n' >> sub/file.txt
  cd sub

  run_grove file-watch --status

  assert_success
  assert_equal "$(display sub/file.txt unstaged | strip_ansi)" "   M  sub/file.txt  +1"
}

# --- The interactive loop --------------------------------------------------------

@test "file-watch: outside a repository exits 0 without starting fzf" {
  cd "${TEST_TMP}"

  run_grove file-watch

  assert_success
  assert_output ""
  assert_equal "$(fzf_call_count)" 0
}

# The stub fzf signals grove after the Nth call, which ends the endless loop.
run_watch() {
  printf '%s\n' "$1" > "${FZF_STUB_DIR}/kill_parent_after"
  run_grove_timeout 20 file-watch
}

@test "file-watch: starts fzf with the expected options" {
  run_watch 1

  assert_equal "${status}" 143
  assert_fzf_arg "--prompt=> "
  assert_fzf_arg "--reverse"
  assert_fzf_arg "--ansi"
  assert_fzf_arg "--info=hidden"
  assert_fzf_arg $'--delimiter=\t'
  assert_fzf_arg "--with-nth=1"
  assert_fzf_arg "--footer=Enter: View  Ctrl-a: Stage  Ctrl-u: Unstage"
}

@test "file-watch: binds reload, view, stage and unstage actions" {
  run_watch 1

  assert_fzf_arg "change:reload:grove file-watch --status"
  assert_fzf_arg "load:reload:sleep 2 && grove file-watch --status"
  assert_fzf_arg 'enter:transform:[[ -n {2} ]] && echo "execute(tmux display-popup -d \"\$PWD\" -w 80% -h 80% -E \"grove show-diff {2} {3}\")"'
  assert_fzf_arg 'ctrl-a:execute-silent(git add -- {2})+reload(grove file-watch --status)'
  assert_fzf_arg 'ctrl-u:execute-silent(git reset HEAD -- {2})+reload(grove file-watch --status)'
}

@test "file-watch: feeds the current status to fzf" {
  printf 'changed\n' > README.md
  printf 'new\n' > new.txt
  run_grove file-watch --status
  local -r expected="${output}"

  run_watch 1

  assert_equal "$(fzf_stdin)" "${expected}"
  assert [ -n "${expected}" ]
}

@test "file-watch: restarts fzf after it exits and pauses between runs" {
  export SLEEP_STUB_LOG="${TEST_TMP}/sleep.log"

  run_watch 3

  assert_equal "${status}" 143
  assert_equal "$(fzf_call_count)" 3
  assert_equal "$(cat "${SLEEP_STUB_LOG}")" $'0.5\n0.5'
}

@test "file-watch: keeps looping when fzf exits non-zero" {
  fzf_exit_code 1

  run_watch 2

  assert_equal "$(fzf_call_count)" 2
}
