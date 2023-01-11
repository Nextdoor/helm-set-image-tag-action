#!/bin/bash

set -eu

# (For future templating...)
COMMIT_MESSAGE="${INPUT_COMMIT_MESSAGE}"

# Sanitize the INPUT_TAG_VALUE. If the tag looks like a github reference
# (refs/tags/* or refs/heads/*) then strip out the prefix and just use the
# last portion of the string.
INPUT_TAG_VALUE=${INPUT_TAG_VALUE//refs\/tags\//}
INPUT_TAG_VALUE=${INPUT_TAG_VALUE//refs\/heads\//}
INPUT_COMMIT_BRANCH=${INPUT_COMMIT_BRANCH//refs\/heads\//}
INPUT_COMMIT_TAG=${INPUT_COMMIT_TAG//refs\/tags\//}


# Take the CSV-submitted list of value files and parse them into an array.
IFS=', ' read -r -a INPUT_VALUES_FILES_ARR <<< "$INPUT_VALUES_FILES"


# This is a workaround for changes in git which introduced strict defaults to
# address https://ubuntu.com/security/CVE-2022-24765.
# In essence, git changed how it executes on multi-user machine/situations, and
# fails when the  directory is owned by a different user than the one executing.
git config --global --add safe.directory /github/workspace;

if [ "${INPUT_FORCE}" == "true" ]; then
  FORCE_OPT="--force"
else
  FORCE_OPT=""
fi

_update_values() {
  # Take the CSV-submitted list of Values "tag" keys and turn it into an
  # array. For each of these values, we'll go and update the yaml.
  local KEYS_ARR
  IFS=', ' read -r -a KEYS_ARR <<< "$INPUT_TAG_KEYS"

  # Create a single YQ eval string that has all of our keys...
  local EXPR
  EXPR=$(printf "( %s = \"${INPUT_TAG_VALUE}\" )|" "${KEYS_ARR[@]}" | sed 's/.$//') || return 1

  # Use `yq` to create the initial change by inline-modifying the files...
  echo "Setting ${EXPR} in ${INPUT_VALUES_FILES_ARR[*]}"...
  yq eval-all "${EXPR}" -i ${INPUT_VALUES_FILES_ARR[*]}
}

_update_chart_version() {
  [ -n "${INPUT_BUMP_LEVEL}" ] || return 0
  echo "Bumping chart version... (bump_level: ${INPUT_BUMP_LEVEL})"
  pybump bump --file $(dirname ${INPUT_VALUES_FILES})/Chart.yaml  --level ${INPUT_BUMP_LEVEL}
}

_update_helm_docs() {
  [ "${INPUT_HELM_DOCS}" == 'true' ] || return 0


  for INPUT_VALUES_FILE in "${INPUT_VALUES_FILES_ARR[@]}"
  do
    echo "Running helm-docs... (helm_docs: ${INPUT_HELM_DOCS}, file: ${INPUT_VALUES_FILE})"
    helm-docs --chart-search-root $(dirname ${INPUT_VALUES_FILE})
  done
}

_git_switch_to_branch(){
  [ -n "${INPUT_COMMIT_BRANCH}" ] || return 0
  git fetch --depth=1
  git checkout ${INPUT_COMMIT_BRANCH}
}

_git_add() {
  # Add in all the changes we've found...
  git add .

  # Print out the git diff
  echo "--- Git Diff ---"
  git diff --cached
}

_git_commit() {
  [ "${INPUT_DRY}" == 'false' ] || return 0

  # shellcheck disable=SC2206
  local INPUT_COMMIT_OPTIONS_ARRAY=( $INPUT_COMMIT_OPTIONS );
  echo "Committing back to the branch"

  # Check that there is a diff to be committed.. 
  git diff --cached --exit-code --quiet && return 0

  git \
    -c user.name="${GITHUB_ACTION}" \
    -c user.email="actions@github.com" \
    commit \
    --author "${GITHUB_ACTOR} <${GITHUB_ACTOR}@users.noreply.github.com>" \
    --message "${COMMIT_MESSAGE}" \
    ${INPUT_COMMIT_OPTIONS:+"${INPUT_COMMIT_OPTIONS_ARRAY[@]}"};
}

_git_tag() {
  [ -n "${INPUT_COMMIT_TAG}" ] || return 0
  echo "Creating tag ${INPUT_COMMIT_TAG}..."
  git tag ${INPUT_COMMIT_TAG} ${FORCE_OPT}
}

_git_push() {
  [ -n "${INPUT_COMMIT_BRANCH}" ] && git push origin "${INPUT_COMMIT_BRANCH}" "${FORCE_OPT}"
  [ -n "${INPUT_COMMIT_TAG}" ] && git push origin "${INPUT_COMMIT_TAG}" "${FORCE_OPT}"
}


# Be really loud and verbose if we're running in VERBOSE mode
if [ "${INPUT_VERBOSE}" == "true" ]; then
  set -x
fi

_git_switch_to_branch
_update_values
_update_chart_version
_update_helm_docs
if [ "${INPUT_COMMIT_AND_PUSH}" == "true" ]; then
  _git_add
  _git_commit
  _git_tag
  _git_push
fi
