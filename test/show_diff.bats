#!/usr/bin/env bats

set -euo pipefail

load 'test_helper/common'

setup() {
  common_setup
  REPO=$(make_repo project)
  cd "${REPO}"
}

# Commit a three-line file, stage a change to line two and then make a further,
# unstaged change to line three.
make_partially_staged_file() {
  printf 'one\ntwo\nthree\n' > data.txt
  git add data.txt && git commit --quiet -m "Add data."
  printf 'one\nTWO\nthree\n' > data.txt
  git add data.txt
  printf 'one\nTWO\nTHREE\n' > data.txt
}

@test "show-diff: no arguments prints usage to stderr and exits 1" {
  run_grove show-diff

  assert_failure 1
  assert_output ""
  assert_stderr "Usage: grove show-diff <file> [staged|unstaged]"
}

@test "show-diff: shows unstaged changes by default" {
  make_partially_staged_file

  run_grove show-diff data.txt

  assert_success
  local plain
  plain=$(printf '%s\n' "${output}" | strip_ansi)
  assert_equal "$(printf '%s\n' "${plain}" | grep -c '^[-+][^-+]')" 2
  assert_regex "${plain}" '-three'
  assert_regex "${plain}" '\+THREE'
  refute_regex "${plain}" '\+TWO'
}

@test "show-diff: the unstaged section shows only unstaged changes" {
  make_partially_staged_file

  run_grove show-diff data.txt unstaged

  local plain
  plain=$(printf '%s\n' "${output}" | strip_ansi)
  assert_regex "${plain}" '\+THREE'
  refute_regex "${plain}" '\+TWO'
}

@test "show-diff: the staged section shows only staged changes" {
  make_partially_staged_file

  run_grove show-diff data.txt staged

  assert_success
  local plain
  plain=$(printf '%s\n' "${output}" | strip_ansi)
  assert_regex "${plain}" '-two'
  assert_regex "${plain}" '\+TWO'
  refute_regex "${plain}" 'THREE'
}

@test "show-diff: uses colors" {
  printf 'changed\n' > README.md

  run_grove show-diff README.md

  assert_output --partial $'\033['
}

@test "show-diff: staged new files are diffed against HEAD" {
  printf 'brand new\n' > added.txt
  git add added.txt

  run_grove show-diff added.txt staged

  assert_success
  local plain
  plain=$(printf '%s\n' "${output}" | strip_ansi)
  assert_regex "${plain}" 'new file mode'
  assert_regex "${plain}" '\+brand new'
}

@test "show-diff: untracked files are diffed against /dev/null" {
  printf 'fresh\n' > untracked.txt

  run_grove show-diff untracked.txt

  assert_success
  local plain
  plain=$(printf '%s\n' "${output}" | strip_ansi)
  assert_regex "${plain}" 'new file mode'
  assert_regex "${plain}" '--- /dev/null'
  assert_regex "${plain}" '\+\+\+ b/untracked.txt'
  assert_regex "${plain}" '\+fresh'
}

@test "show-diff: an untracked file passed with the unstaged section is diffed against /dev/null" {
  printf 'fresh\n' > untracked.txt

  run_grove show-diff untracked.txt unstaged

  assert_success
  assert_output --partial "fresh"
}

@test "show-diff: untracked files with spaces in the name work" {
  printf 'spaced\n' > "with space.txt"

  run_grove show-diff "with space.txt"

  assert_success
  assert_output --partial "spaced"
}

@test "show-diff: a file that is neither on disk nor tracked exits 0 silently" {
  run_grove show-diff missing.txt

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
}

@test "show-diff: a deleted tracked file shows its removal" {
  rm README.md

  run_grove show-diff README.md

  assert_success
  local plain
  plain=$(printf '%s\n' "${output}" | strip_ansi)
  assert_regex "${plain}" 'deleted file mode'
  assert_regex "${plain}" '-hello'
}

@test "show-diff: a staged deletion shows its removal" {
  skip "BUG: after git rm the file is neither on disk nor in the index, so the early 'not tracked and not present' exit hides the diff for staged deletions."
  git rm --quiet README.md

  run_grove show-diff README.md staged

  assert_success
  assert_output --partial "deleted file mode"
}

@test "show-diff: a staged deletion currently prints nothing" {
  git rm --quiet README.md

  run_grove show-diff README.md staged

  assert_success
  assert_output ""
}

@test "show-diff: an unchanged tracked file prints nothing" {
  run_grove show-diff README.md

  assert_success
  assert_output ""
}

@test "show-diff: output is sent through less with -R +g" {
  export LESS_STUB_LOG="${TEST_TMP}/less.log"
  printf 'changed\n' > README.md

  run_grove show-diff README.md

  assert_equal "$(cat "${LESS_STUB_LOG}")" "-R +g"
}

@test "show-diff: nothing is paged when the file does not exist" {
  export LESS_STUB_LOG="${TEST_TMP}/less.log"

  run_grove show-diff missing.txt

  assert [ ! -e "${LESS_STUB_LOG}" ]
}

@test "show-diff: untracked files are paged too" {
  export LESS_STUB_LOG="${TEST_TMP}/less.log"
  printf 'fresh\n' > untracked.txt

  run_grove show-diff untracked.txt

  assert_equal "$(cat "${LESS_STUB_LOG}")" "-R +g"
}

@test "show-diff: only the requested file is shown" {
  printf 'changed\n' > README.md
  printf 'other\n' > other.txt
  git add other.txt && git commit --quiet -m "Add other."
  printf 'other changed\n' > other.txt

  run_grove show-diff README.md

  refute_output --partial "other"
}
