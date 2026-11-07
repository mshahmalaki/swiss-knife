#!/usr/bin/env sh
# Resolve the latest stable version of every tool baked into the image.
# Prints KEY=VALUE lines (suitable for `eval`, `.env` or $GITHUB_ENV).
# Any variable already set in the environment is kept as-is, so you can pin
# a single tool, e.g.:  KUBE_VERSION=1.33.0 make docker_build
set -eu

# Latest semver tag (vX.Y.Z, no pre-releases) of a GitHub repo, without the "v".
# Uses git ls-remote, so it is not subject to GitHub API rate limits.
gh_latest() {
  git ls-remote --tags --refs "https://github.com/$1.git" \
    | sed -n 's#.*refs/tags/v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$#\1#p' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n1
}

pypi_latest() {
  curl -fsSL "https://pypi.org/pypi/$1/json" \
    | sed -n 's/.*"info":{.*"version":"\([^"]*\)".*/\1/p' | head -n1
}

alpine_latest() {
  curl -fsSL https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml \
    | sed -n 's/^ *version: *\([0-9.]*\).*/\1/p' | head -n1
}

kube_latest() { curl -fsSL https://dl.k8s.io/release/stable.txt | sed 's/^v//'; }

terraform_latest() {
  curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform \
    | sed -n 's/.*"current_version":"\([^"]*\)".*/\1/p'
}

emit() {
  name=$1; shift
  eval "val=\${$name:-}"
  [ -n "$val" ] || val=$("$@")
  if [ -z "$val" ]; then
    echo "error: could not resolve $name" >&2
    exit 1
  fi
  echo "$name=$val"
}

go_latest() { curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1 | sed 's/^go//'; }

emit ALPINE_VERSION     alpine_latest
emit GO_VERSION         go_latest
emit KUBE_VERSION       kube_latest
emit HELM_VERSION       gh_latest helm/helm
emit HELM_PUSH_VERSION  gh_latest chartmuseum/helm-push
emit TERRAFORM_VERSION  terraform_latest
emit YQ_VERSION         gh_latest mikefarah/yq
emit PIP_VERSION        pypi_latest pip
emit SETUPTOOLS_VERSION pypi_latest setuptools
emit TEMPLER_VERSION    pypi_latest docker-compose-templer
emit JINJA_VERSION      pypi_latest Jinja2
