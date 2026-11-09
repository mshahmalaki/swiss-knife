.DEFAULT_GOAL := docker_build

# Optional pins: any uncommented VAR=value in .env overrides "latest".
-include .env
export

DOCKER_IMAGE ?= hesamyavari/swiss-knife
DOCKER_TAG   ?= $(shell git rev-parse --abbrev-ref HEAD)
PLATFORMS    ?= linux/amd64,linux/arm64
BUILDER      ?= swiss-knife

BUILD_ARGS := ALPINE_VERSION GO_VERSION KUBE_VERSION HELM_VERSION HELM_PUSH_VERSION TERRAFORM_VERSION \
              YQ_VERSION PIP_VERSION SETUPTOOLS_VERSION TEMPLER_VERSION JINJA_VERSION \
              ALPINE_EDGE_PACKAGES

# Resolve the latest versions once, export them, then run buildx.
# `--build-arg NAME` without a value takes NAME from the environment.
# --pull + --no-cache: always start from the newest base image and re-run
# `apk upgrade`, so a cached layer never ships stale (vulnerable) packages.
define buildx
	@set -e; \
	versions="$$(./scripts/versions.sh)"; \
	echo "$$versions"; \
	eval "$$(echo "$$versions" | sed 's/^/export /')"; \
	docker buildx build --builder $(BUILDER) --pull --no-cache \
	  $(foreach a,$(BUILD_ARGS),--build-arg $(a)) \
	  $(1) \
	  -t $(DOCKER_IMAGE):$(DOCKER_TAG) \
	  -t $(DOCKER_IMAGE):latest \
	  .
endef

.PHONY: versions builder docker_build docker_push

# Show the versions the next build will use
versions:
	@./scripts/versions.sh

# Multi-platform builder with limited parallelism (buildkitd.toml), created once
builder:
	@docker buildx inspect $(BUILDER) > /dev/null 2>&1 || \
	  docker buildx create --name $(BUILDER) --driver docker-container \
	    --buildkitd-config buildkitd.toml --bootstrap

# Build for the local platform and load into the local docker
docker_build: builder
	$(call buildx,--load)

# Build for all PLATFORMS and push a multi-arch manifest to the registry
docker_push: builder
	$(call buildx,--platform $(PLATFORMS) --push)
