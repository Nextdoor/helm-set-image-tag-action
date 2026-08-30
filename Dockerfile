FROM alpine:3.18

LABEL "com.github.actions.name"="Helm Set Image Tag Action"
LABEL "com.github.actions.description"="A Github Action for automatically updating a Helm template image tag"
LABEL "com.github.actions.icon"="arrow-up"
LABEL "com.github.actions.color"="green"

LABEL "repository"="https://github.com/Nextdoor/helm-set-image-tag-action"
LABEL "homepage"="https://github.com/Nextdoor/helm-set-image-tag-action"
LABEL "maintainer"="diranged"

# No Python here on purpose. This is a Docker action, so this image is built
# by the runner during job setup -- before step 1, and therefore before any
# `aws-login` step could authenticate a package index. `pip install` from
# public PyPI is unroutable at this point by construction, so the four Python
# packages this image used to install have been removed instead:
#   * yamale, yamllint and pyyaml were never referenced by entrypoint.sh;
#   * pybump was replaced by the `yq` + bash bump in `_bump_semver`.
# py-pip, py3-ruamel.yaml, gcc, musl-dev and python3-dev existed only to
# support that `pip install` and are dropped with it.
RUN apk --no-cache add bash yq git patch

COPY --from=alpine/helm:latest /usr/bin/helm /usr/bin/helm
COPY --from=jnorwood/helm-docs:v1.11.3 /usr/bin/helm-docs /usr/bin/helm-docs

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
