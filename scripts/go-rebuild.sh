#!/bin/sh
# Rebuild a Go tool from source with the current Go toolchain and the latest
# (same-major) versions of the dependencies that commonly carry CVEs.
#
# Usage: go-rebuild.sh <src-dir> <main-package> <output> [ldflags]
# GOOS/GOARCH from the environment select the target platform.
set -eu

src=$1; pkg=$2; out=$3; ldflags=${4:-}
cd "$src"

# Dependency families to move to their latest release. Only those actually in
# the module graph are upgraded; the main module itself is skipped.
pattern='^(golang\.org/x/(crypto|net|text|sys|oauth2|image|term|time|sync)|google\.golang\.org/(grpc|protobuf)|github\.com/klauspost/compress|github\.com/containerd/containerd(/v2)?|oras\.land/oras-go/v2|github\.com/cloudflare/circl|helm\.sh/helm/v[34]|github\.com/opencontainers/runc|github\.com/docker/docker|github\.com/golang-jwt/jwt/v[45]|go\.opentelemetry\.io/otel[a-z/]*)$'

main=$(go list -m)
mods=$(go list -m -f '{{if not .Main}}{{.Path}}{{end}}' all | grep -E "$pattern" | grep -vx "$main" | sort -u || true)

if [ -n "$mods" ]; then
  # shellcheck disable=SC2086
  go get $(printf '%s@latest ' $mods)
fi
go mod tidy

CGO_ENABLED=0 go build -p "${GO_BUILD_PARALLELISM:-4}" -trimpath -buildvcs=false -ldflags "-s -w $ldflags" -o "$out" "$pkg"
