# Where the base images come from. The default is Docker Hub. Set the
# `base_image_registry` input to pull them through a registry mirror instead;
# the mirror must use Docker Hub's paths (for example `library/alpine`).
ARG REGISTRY=docker.io

FROM ${REGISTRY}/alpine/helm:4.3.1 AS helm
FROM ${REGISTRY}/jnorwood/helm-docs:v1.11.3 AS helm-docs

FROM ${REGISTRY}/library/alpine:3.18

LABEL "com.github.actions.name"="Helm Set Image Tag Action"
LABEL "com.github.actions.description"="A Github Action for automatically updating a Helm template image tag"
LABEL "com.github.actions.icon"="arrow-up"
LABEL "com.github.actions.color"="green"

LABEL "repository"="https://github.com/Nextdoor/helm-set-image-tag-action"
LABEL "homepage"="https://github.com/Nextdoor/helm-set-image-tag-action"
LABEL "maintainer"="diranged"

# No Python here on purpose. This image used to be built by the runner during
# job setup -- before step 1, and therefore before any step could configure a
# package index. A `pip install` here always goes to public PyPI and fails
# wherever PyPI isn't reachable, so the four Python packages this image used
# to install have been removed instead:
#   * yamale, yamllint and pyyaml were never referenced by entrypoint.sh;
#   * pybump was replaced by the `yq` + bash bump in `_bump_semver`.
# py-pip, py3-ruamel.yaml, gcc, musl-dev and python3-dev existed only to
# support that `pip install` and are dropped with it.
RUN apk --no-cache add bash yq git patch

COPY --from=helm /usr/bin/helm /usr/bin/helm
COPY --from=helm-docs /usr/bin/helm-docs /usr/bin/helm-docs

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
