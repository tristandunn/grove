#!/usr/bin/env bash
#
# Runs once before any test file. bats finds this file next to the .bats files,
# both for the whole suite and for a single file.

setup_suite() {
  export REPO_TEMPLATE="${BATS_SUITE_TMPDIR}/repo-template"

  # Build the repository that make_repo copies into every test. The subshell
  # keeps the strict mode and git environment of the helpers out of bats itself.
  (
    load 'test_helper/common'
    export_git_environment "${BATS_SUITE_TMPDIR}"
    build_repo_template "${REPO_TEMPLATE}"
  )
}
