# `helm-set-image-tag-action`

This action is designed to help you automatically update your Helm charts to
point to the most recent releases of your application (ie, a Docker Image Tag)
and rev your Helm Chart accordingly. The goal is to create a continuous
delivery process that is entirely Git based.

## Basic Flow

The general idea here is that a human being decides to release a new version of
an application from their repository - so a developer creates a Github Release
to rev the version of their application (say from `v1.2.2` to `v1.2.3`) after
sufficient testing has been done.

Once that has been done, we want to fully automate the process of updating the
Helm `values.yaml` file, as well as revving the `Chart.yaml` version key, and
even updating the Helm Documentation. Here is an example flow.

1. Developer commits code into `HEAD` in their repository.
2. Testing and iteration occurs on that code...
3. Developer tags new release `v1.2.3` pointing to SHA `abcdefg1`.
3. CI system builds Docker artifact `myapp:v1.2.3`
   (hint: [Nextdoor/docker-image-retag-action][docker-image-retag-action])
4. This action is triggered and runs through a few steps:
   1. Updates the `values.yaml` file and sets `image.tag: v1.2.3`
   2. Updates the `Chart.yaml` and automatically revs the version from `0.1.42` to `0.1.43`
   3. Re-generates the Helm Documentation to match
   4. Commits all of the above changes back to a target branch (if `commit_branch` is set)
   5. Creates a release tag that points to the newly created commit (if `commit_tag` is set)

### Understanding `commit_branch`

When you set `commit_branch`, the action starts by checking out the branch you've supplied. This is done so that the newly created commit 

### Understanding `commit_tag`

## Usage

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    branches:
      # Generally you probably do not want to run this on branches because
      # you'll get a new Helm Chart version commit for every single commit into
      # your branch. It would be very noisy.
      - '!*'
    tags:
      # Trigger this on the tag format that your developers are using for the
      # core application/docker-image tag.
      - v*
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@master
      with:
        fetch-depth: '0'  # this is important for the git writeback

    - name: Retag Docker Image for Production
      uses: Nextdoor/docker-image-retag-action@main
        ...

    - name: Update Helm Chart Values
      uses: Nextdoor/helm-set-image-tag-action@main
      with:
        # A comma-separated list of Values files to update. We default to
        # `chart/values.yaml`, but you can patch multiple values files at once if
        # you need to. There should be only one chart being updated though. To
        # update multiple charts, run this action multiple times.
        #
        values_files: charts/app/values.yaml

        # A comma-separated list of keys to update within the Values file(s).
        # The keys should be in Dot-notation and always start with a `.`. Only
        # one "value" can be applied to these tags (see `tag_value` below) - so
        # multiple keys here only makes sense if you use the image tag value in
        # multiple places inside your chart.
        #
        # tag_keys: .image.tag

        # This is the value that will be set in the Values files on the Tag
        # Keys (see above). If this build is running on git tag `v1.2.3` and your
        # docker image tag is `release-v1.2.3`, then you would set this to
        # `release-${{ github.ref }}`
        #
        tag_value: ${{ github.ref }}

        # This is the sem-ver level that will be bumped for each release.
        # `major`, `minor`, `path` or `null` are allowed. If you set `null` then
        # it will skip bumping the version.
        #
        # bump_level: patch

        # `true` or `false` - whether or not to run the helm-docs generator.
        #
        # helm_docs: true

        # Generally you want to set this to whatever your primary `HEAD` commit
        # points to (`main` or `master` typically). Without setting this, a
        # detached-commit will be created but no pointer will exist for it. You
        # will need to introduce your own code to create a branch or tag that
        # points to this commit.
        #
        commit_branch: main

        # Instead of (or in addition to) putting the newly created release
        # commit on the $commit_branch, you can also create a tag that points to
        # this commit. This allows you to avoid writing back to main if you
        # prefer to use git tags to maintain your releases. 
        #
        # In this example, we take the "tag name" that we were triggered on and
        # create a new tag appending "-chart" to it.
        #
        commit_tag: ${{ github.ref }}-chart

        # Whether to commit and push to the remote repository, default to true.
        # You can modify multiple keys and values in the values file by calling
        # this action multiple times but only setting commit_and_push to true in
        # the last call.
        #
        # commit_and_push: true

        # Override the message used in the git commit.
        #
        # commit_message: Automated commit on behalf-of ${{ github.actor }}

        # Optional commit arguments
        #
        # commit_options: ''

        # Set the action to run in `set -x` mode for very verbose logging. Set
        # to `true` or `false`.
        #
        # verbose: false

        # Optionally run the action in 'dry' mode - where all of the normal
        # actions happen, but no `git commit` happens. Useful for initial testing
        # of the configuration. Set to `true` or `false`.
        #
        # dry: false
```
