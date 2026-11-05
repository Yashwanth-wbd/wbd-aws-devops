#!/usr/bin/env bash
# Lambda release helpers used by .github/workflows/deploy.yml (results publisher).
#
#   lambda-release.sh build   <app-dir> <zip>              -> zip of the code + requirements.txt (Linux x86_64 wheels), prints sha256
#   lambda-release.sh current <function>                   -> prints the version alias "live" points to
#   lambda-release.sh publish <function> <zip> <version>   -> uploads, publishes a version, moves "live", prints the new version
#   lambda-release.sh switch  <function> <version>         -> moves "live" to <version> (rollback)
#
# Terraform owns the function configuration (role, VPC, env vars, alias); this only ships code.
set -euo pipefail

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"

die() { echo "::error::$*" >&2; exit 1; }

build() {
  local app_dir="$1" zip pkg
  zip=$(realpath -m "$2")
  [ -d "$app_dir" ] || die "$app_dir does not exist"
  pkg=$(mktemp -d)
  if [ -f "$app_dir/requirements.txt" ]; then
    pip install --quiet --requirement "$app_dir/requirements.txt" --target "$pkg" \
      --platform manylinux2014_x86_64 --implementation cp --python-version "$PYTHON_VERSION" --only-binary=:all:
  fi
  (cd "$app_dir" && find . -name '*.py' -not -path './tests/*' -exec cp --parents {} "$pkg" \;)
  rm -f "$zip"
  (cd "$pkg" && find . -type f -exec touch -d '2000-01-01T00:00:00Z' {} + && find . -type f | sort | zip -q -X "$zip" -@)
  rm -rf "$pkg"
  sha256sum "$zip" | cut -d' ' -f1
}

current() {
  aws lambda get-alias --function-name "$1" --name live --query FunctionVersion --output text
}

publish() {
  local fn="$1" zip="$2" version="$3" new
  aws lambda update-function-code --function-name "$fn" --zip-file "fileb://$zip" > /dev/null
  aws lambda wait function-updated-v2 --function-name "$fn"
  new=$(aws lambda publish-version --function-name "$fn" --description "$version" --query Version --output text)
  aws lambda update-alias --function-name "$fn" --name live --function-version "$new" > /dev/null
  echo "$fn: live -> version $new ($version)" >&2
  echo "$new"
}

switch() {
  aws lambda update-alias --function-name "$1" --name live --function-version "$2" > /dev/null
  echo "$1: live -> version $2"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  build)   [ $# -eq 2 ] || die "usage: build <app-dir> <zip>"; build "$@" ;;
  current) [ $# -eq 1 ] || die "usage: current <function>"; current "$@" ;;
  publish) [ $# -eq 3 ] || die "usage: publish <function> <zip> <version>"; publish "$@" ;;
  switch)  [ $# -eq 2 ] || die "usage: switch <function> <version>"; switch "$@" ;;
  *) die "usage: lambda-release.sh build|current|publish|switch ..." ;;
esac
