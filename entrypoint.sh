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
  for INPUT_VALUES_FILE in "${INPUT_VALUES_FILES_ARR[@]}"
  do
    echo "Setting ${EXPR} in ${INPUT_VALUES_FILE}"...
    yq eval-all "${EXPR}" -i ${INPUT_VALUES_FILE}
  done
}

# Bump the `version:` key of a Helm Chart.yaml in place, using `yq` and bash.
#
# This replaces `pybump bump`, which was the only reason this image contained
# Python at all. A Docker action's image is built by the runner during *job
# setup*, before step 1 of the job -- so no `aws-login` step can ever run
# early enough to authenticate a package install here, and no build secret is
# reachable. The dependency therefore has to go, rather than be re-routed.
#
# Behaviour is matched to pybump 1.14.2, which is what this image installed:
#   * the file must be a Helm chart (apiVersion + name + version), else fail;
#   * the version is semver, with an optional lower-case `v` prefix, an
#     optional `-release` and an optional `+metadata`; all three are preserved;
#   * major and minor and patch components reject leading zeros;
#   * major -> (X+1).0.0 , minor -> X.(Y+1).0 , patch -> X.Y.(Z+1);
#   * the resulting version is echoed to stdout;
#   * on any validation failure nothing is written and the action fails.
_bump_semver() {
  local version="$1" level="$2"
  local prefix='' release='' metadata='' core part major minor patch

  # An optional lower-case 'v' prefix is allowed and preserved.
  case "${version}" in v*) prefix='v'; version="${version#v}" ;; esac

  # Split '+metadata' before '-release': build metadata is always last.
  case "${version}" in *+*) metadata="${version#*+}"; version="${version%%+*}" ;; esac
  case "${version}" in *-*) release="${version#*-}";  version="${version%%-*}" ;; esac
  core="${version}"

  if ! [[ "${core}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    return 1
  fi
  major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; patch="${BASH_REMATCH[3]}"

  # Dot-separated pre-release identifiers: numeric (no leading zeros) or
  # alphanumeric/hyphen. Build-metadata identifiers are alphanumeric/hyphen.
  if [ -n "${release}" ]; then
    local IFS=.
    for part in ${release}; do
      [[ "${part}" =~ ^(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)$ ]] || return 1
    done
  fi
  if [ -n "${metadata}" ]; then
    local IFS=.
    for part in ${metadata}; do
      [[ "${part}" =~ ^[0-9a-zA-Z-]+$ ]] || return 1
    done
  fi

  case "${level}" in
    major) major=$(( major + 1 )); minor=0; patch=0 ;;
    minor) minor=$(( minor + 1 )); patch=0 ;;
    patch) patch=$(( patch + 1 )) ;;
    *)
      echo "Error, invalid level: '${level}', should be major|minor|patch." >&2
      return 1
      ;;
  esac

  printf '%s%s.%s.%s%s%s\n' \
    "${prefix}" "${major}" "${minor}" "${patch}" \
    "${release:+-${release}}" "${metadata:++${metadata}}"
}

_update_chart_version() {
  [ -n "${INPUT_BUMP_LEVEL}" ] || return 0
  echo "Bumping chart version... (bump_level: ${INPUT_BUMP_LEVEL})"

  local CHART_FILE
  CHART_FILE=$(dirname ${INPUT_VALUES_FILES})/Chart.yaml

  # Same mandatory-key check pybump made before touching anything.
  if [ "$(yq eval '[has("apiVersion"), has("name"), has("version")] | all' "${CHART_FILE}")" != "true" ]; then
    echo "Input file is not a valid Helm chart.yaml: ${CHART_FILE}" >&2
    return 1
  fi

  local CURRENT NEW
  CURRENT=$(yq eval '.version' "${CHART_FILE}")

  if ! NEW=$(_bump_semver "${CURRENT}" "${INPUT_BUMP_LEVEL}"); then
    echo "Invalid semantic version format: ${CURRENT}" >&2
    echo "Make sure to comply with https://semver.org/ (lower case 'v' prefix is allowed)" >&2
    return 1
  fi

  NEW="${NEW}" yq eval -i '.version = strenv(NEW)' "${CHART_FILE}"
  echo "${NEW}"
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
  return 0
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
