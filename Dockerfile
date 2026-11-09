# syntax=docker/dockerfile:1
# Tool versions are resolved to the latest release by scripts/versions.sh
# and passed in as build args (see Makefile and the CI workflow).
ARG ALPINE_VERSION=latest
ARG GO_VERSION=1

# ---------------------------------------------------------------------------
# Go tools are rebuilt from source with the latest Go toolchain and patched
# dependencies (scripts/go-rebuild.sh). Upstream release binaries often lag
# behind on Go/x-net/x-crypto security fixes. Stages run in parallel on the
# build host and cross-compile for the target platform (no emulation).
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS gobuild
RUN apk add --no-cache git
COPY scripts/go-rebuild.sh /usr/local/bin/go-rebuild
ENV CGO_ENABLED=0

FROM gobuild AS kubectl
ARG KUBE_VERSION
ARG TARGETOS
ARG TARGETARCH
RUN git clone -q --depth 1 --branch v${KUBE_VERSION} https://github.com/kubernetes/kubernetes /src
# Kubernetes uses a go.work workspace + vendor dir; build in plain module mode
# so dependency upgrades apply (staging modules resolve via replace directives).
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    export GOWORK=off GOFLAGS=-mod=mod GOOS=${TARGETOS} GOARCH=${TARGETARCH}; \
    minor=$(echo "${KUBE_VERSION}" | cut -d. -f2); ld=""; \
    for p in k8s.io/client-go/pkg/version k8s.io/component-base/version; do \
      ld="$ld -X $p.gitVersion=v${KUBE_VERSION} -X $p.gitMajor=1 -X $p.gitMinor=${minor} -X $p.gitTreeState=clean"; \
    done; \
    go-rebuild /src ./cmd/kubectl /out/kubectl "$ld"

FROM gobuild AS helm
ARG HELM_VERSION
ARG TARGETOS
ARG TARGETARCH
RUN git clone -q --depth 1 --branch v${HELM_VERSION} https://github.com/helm/helm /src
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} go-rebuild /src ./cmd/helm /out/helm \
      "-X helm.sh/helm/v${HELM_VERSION%%.*}/internal/version.version=v${HELM_VERSION} -X helm.sh/helm/v${HELM_VERSION%%.*}/internal/version.gitTreeState=clean"

FROM gobuild AS helm-push
ARG HELM_PUSH_VERSION
ARG HELM_VERSION
ARG TARGETOS
ARG TARGETARCH
RUN git clone -q --depth 1 --branch v${HELM_PUSH_VERSION} https://github.com/chartmuseum/helm-push /src
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} go-rebuild /src ./cmd/helm-cm-push /out/bin/helm-cm-push \
    && cp /src/LICENSE /out/ \
    # Same manifest selection as upstream's scripts/install_plugin.sh
    && cp "/src/testdata/plugin-helm${HELM_VERSION%%.*}.yaml" /out/plugin.yaml

FROM gobuild AS terraform
ARG TERRAFORM_VERSION
ARG TARGETOS
ARG TARGETARCH
RUN git clone -q --depth 1 --branch v${TERRAFORM_VERSION} https://github.com/hashicorp/terraform /src
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} go-rebuild /src . /out/terraform \
      "-X github.com/hashicorp/terraform/version.dev=no"

FROM gobuild AS yq
ARG YQ_VERSION
ARG TARGETOS
ARG TARGETARCH
RUN git clone -q --depth 1 --branch v${YQ_VERSION} https://github.com/mikefarah/yq /src
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} go-rebuild /src . /out/yq

# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION}

ARG GO_VERSION
ARG KUBE_VERSION
ARG HELM_VERSION
ARG HELM_PUSH_VERSION
ARG TERRAFORM_VERSION
ARG YQ_VERSION
ARG PIP_VERSION
ARG SETUPTOOLS_VERSION
ARG TEMPLER_VERSION
ARG JINJA_VERSION
# Packages taken from Alpine edge because the stable branch has not shipped
# their security fixes yet. Empty this (in .env) once stable catches up.
ARG ALPINE_EDGE_PACKAGES="musl musl-utils openssh-client-default openssh-client-common openssh-keygen sqlite-libs"

# Fail fast with a clear message if the image is built without the version args.
RUN : "${KUBE_VERSION:?build with 'make docker_build' or pass --build-arg KUBE_VERSION}" \
      "${HELM_VERSION:?missing HELM_VERSION}" "${HELM_PUSH_VERSION:?missing HELM_PUSH_VERSION}" \
      "${TERRAFORM_VERSION:?missing TERRAFORM_VERSION}" "${YQ_VERSION:?missing YQ_VERSION}" \
      "${PIP_VERSION:?missing PIP_VERSION}" "${SETUPTOOLS_VERSION:?missing SETUPTOOLS_VERSION}" \
      "${TEMPLER_VERSION:?missing TEMPLER_VERSION}" "${JINJA_VERSION:?missing JINJA_VERSION}"

RUN apk -U upgrade \
    && apk add --no-cache bash ca-certificates curl gettext-envsubst git jq openssh-client python3 \
        mtr tcpdump iproute2 vim tini \
    && if [ -n "${ALPINE_EDGE_PACKAGES}" ]; then \
         echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories \
         && apk add --no-cache $(printf '%s@edge ' ${ALPINE_EDGE_PACKAGES}); \
       fi \
    && mkdir /config \
    && chmod g+rwx /config /root

COPY --from=kubectl   /out/kubectl   /usr/local/bin/kubectl
COPY --from=helm      /out/helm      /usr/local/bin/helm
COPY --from=terraform /out/terraform /usr/local/bin/terraform
COPY --from=yq        /out/yq        /usr/local/bin/yq
COPY --from=helm-push /out           /root/.local/share/helm/plugins/helm-push

RUN kubectl version --client \
    && helm version \
    && terraform version \
    && yq --version \
    && helm cm-push --help > /dev/null \
    && helm repo add "stable" "https://charts.helm.sh/stable" --force-update

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
RUN pip install --no-cache-dir --upgrade "pip==${PIP_VERSION}" "setuptools==${SETUPTOOLS_VERSION}" \
    && pip install --no-cache-dir "docker-compose-templer==${TEMPLER_VERSION}" "Jinja2==${JINJA_VERSION}"

# Record what went into this image: docker run --rm <image> cat /etc/swiss-knife-versions
RUN printf '%s\n' \
      "alpine=$(cat /etc/alpine-release)" \
      "go=${GO_VERSION} (kubectl, helm, helm-push, terraform, yq rebuilt from source)" \
      "kubectl=${KUBE_VERSION}" \
      "helm=${HELM_VERSION}" \
      "helm-push=${HELM_PUSH_VERSION}" \
      "terraform=${TERRAFORM_VERSION}" \
      "yq=${YQ_VERSION}" \
      "pip=${PIP_VERSION}" \
      "setuptools=${SETUPTOOLS_VERSION}" \
      "docker-compose-templer=${TEMPLER_VERSION}" \
      "jinja2=${JINJA_VERSION}" \
      "alpine-edge-packages=${ALPINE_EDGE_PACKAGES:-none}" \
      > /etc/swiss-knife-versions

WORKDIR /config

# Long-running by default so the image can live as a Pod/Deployment in
# Kubernetes and be used via `kubectl exec -it <pod> -- bash`.
# tini (PID 1) forwards signals and reaps zombies, so the pod stops instantly.
# Override the command for one-off use: docker run --rm -it <image> bash
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sleep", "infinity"]
