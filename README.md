# Swiss Knife Docker image for DevOps

[![ci](https://github.com/hesamyavari/swiss-knife/actions/workflows/image-build-push.yaml/badge.svg?branch=main)](https://github.com/hesamyavari/swiss-knife/actions/workflows/image-build-push.yaml)
[![Docker Stars](https://img.shields.io/docker/stars/hesamyavari/swiss-knife.svg?style=flat)](https://hub.docker.com/r/hesamyavari/swiss-knife/)
[![Docker Pulls](https://img.shields.io/docker/pulls/hesamyavari/swiss-knife.svg?style=flat)](https://hub.docker.com/r/hesamyavari/swiss-knife/)

## Tools

Each build picks up the **latest stable release** of every tool:

* Alpine
* kubectl
* Helm + helm-push plugin
* Terraform
* yq
* docker-compose-templer, Jinja2 (in a Python venv with the latest pip/setuptools)
* bash, git, curl, jq, envsubst, openssh-client, mtr, tcpdump, iproute2 (`ip`, `ss`), vim

The CI rebuilds the image every Monday, so `latest` stays current. To see the exact versions inside an image:

`docker run --rm hesamyavari/swiss-knife cat /etc/swiss-knife-versions`

### Security

* kubectl, helm, helm-push, terraform and yq are **built from source** with the latest Go
  toolchain and patched dependencies ([scripts/go-rebuild.sh](scripts/go-rebuild.sh)),
  instead of using upstream binaries that often ship with outdated Go libraries.
* Every build starts from a fresh base image and runs `apk upgrade` (no layer cache).
* Alpine packages whose fixes have not reached the stable branch yet are taken from
  Alpine edge (`ALPINE_EDGE_PACKAGES` in the Dockerfile; override/empty it in `.env`).

## Overview

This lightweight alpine docker image provides kubectl and helm binaries for working with a Kubernetes cluster. A local configured kubectl is a prerequisite to use helm per [helm documentation](https://github.com/kubernetes/helm/blob/master/docs/quickstart.md). This image is useful for general helm administration such as deploying helm charts and managing releases. It is also perfect for any automated deployment pipeline needing to use helm which supports docker images such as [Concourse CI](https://concourse.ci), [Jenkins on Kubernetes](https://kubeapps.com/charts/stable/jenkins), [Travis CI](https://docs.travis-ci.com/user/docker/), and [Circle CI](https://circleci.com/integrations/docker/). Having bash installed allows for better support for troubleshooting by being able to exec / terminal in and run desired shell scripts. Git installed allows installation of [helm plugins](https://github.com/kubernetes/helm/blob/master/docs/plugins.md).

If it is desired to only use kubectl and have kubectl as the entry command (versus this image as bash entry command), I recommend checking out this image instead:
[lachlanevenson/kubectl](https://hub.docker.com/r/lachlanevenson/k8s-kubectl/)

## Run

Example to just run helm on entry:  
`docker run --rm hesamyavari/swiss-knife helm`
By default kubectl will try to use /root/.kube/config file for connection to the kubernetes cluster, but does not exist by default in the image.

Example for use with personal administration or troubleshooting with volume mount for kubeconfig files:  
`docker run -it -v ~/.kube:/root/.kube hesamyavari/swiss-knife`
The -v maps your host docker machine Kubernetes configuration directory (~/.kube) to the container's Kubernetes configuration directory (root/.kube).

## Build

Published images support `linux/amd64` and `linux/arm64`.

Versions are resolved by [scripts/versions.sh](scripts/versions.sh) at build time.

```sh
make versions       # show the versions the next build will use
make docker_build   # build for your local platform and load it into docker
make docker_push    # build linux/amd64 + linux/arm64 and push a multi-arch image
```

To pin a tool, uncomment its line in `.env`, or set it for one build:
`KUBE_VERSION=1.36.0 make docker_build`

`make docker_push` needs a buildx builder that supports multi-platform builds, e.g.
`docker buildx create --use --name multiarch` (Docker Desktop's default builder also works).
