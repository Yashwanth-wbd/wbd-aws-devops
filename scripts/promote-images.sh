#!/usr/bin/env bash
# Moves an already-built image to the next environment's ECR without rebuilding (same digest).
#
#   promote-images.sh login      <registry>                        -> skopeo login with the current AWS credentials
#   promote-images.sh find-build <repository> <app-dir> <commit>   -> prints sha-<7> of the image that contains <commit>'s <app-dir>
#   promote-images.sh find-rc    <vX.Y.Z> <commit>                 -> prints the newest vX.Y.Z-rcN tag on <commit>
#   promote-images.sh copy       <source-ref> <target-ref>         -> copies, keeps the digest, prints it
#
# Login to the source registry with the source account's ecr-read role, and to the target with
# the target account's ecr-push role, before copy. Credentials are kept in REGISTRY_AUTH_FILE.
set -euo pipefail

export REGISTRY_AUTH_FILE="${REGISTRY_AUTH_FILE:-${RUNNER_TEMP:-/tmp}/registry-auth.json}"

die() { echo "::error::$*" >&2; exit 1; }

login() {
  aws ecr get-login-password | skopeo login --username AWS --password-stdin "$1" > /dev/null
  echo "Logged in to $1"
}

image_exists() {
  aws ecr describe-images --repository-name "$1" --image-ids "imageTag=$2" > /dev/null 2>&1
}

# CI builds an app only when its folder changes, so the image for a commit is the newest
# ancestor build - as long as the folder did not change after it.
find_build() {
  local repo="$1" app_dir="$2" commit="$3" c tag
  for c in $(git rev-list --max-count=300 "$commit"); do
    tag="sha-${c:0:7}"
    if image_exists "$repo" "$tag"; then
      git diff --quiet "$c" "$commit" -- "$app_dir" ||
        die "$app_dir changed after $tag, but no image was built for that change (check the CI run on main)"
      echo "$tag"
      return 0
    fi
  done
  die "no $repo image found for $commit or its last 300 ancestors"
}

find_rc() {
  local version="$1" commit="$2" rc
  rc=$(git tag --points-at "$commit" --list "${version}-rc*" | sort -V | tail -n 1)
  [ -n "$rc" ] || die "$version must be tagged on a commit that was released to staging as ${version}-rcN"
  echo "$rc"
}

copy() {
  local src="$1" dst="$2" src_digest dst_digest
  src_digest=$(skopeo inspect --format '{{.Digest}}' "docker://$src")
  if dst_digest=$(skopeo inspect --format '{{.Digest}}' "docker://$dst" 2>/dev/null); then
    [ "$dst_digest" = "$src_digest" ] || die "$dst already exists with a different digest ($dst_digest)"
    echo "$dst already present ($dst_digest)" >&2
  else
    skopeo copy --all --preserve-digests --retry-times 3 "docker://$src" "docker://$dst" >&2
    echo "Copied $src -> $dst" >&2
  fi
  echo "$src_digest"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  login)      [ $# -eq 1 ] || die "usage: login <registry>"; login "$@" ;;
  find-build) [ $# -eq 3 ] || die "usage: find-build <repository> <app-dir> <commit>"; find_build "$@" ;;
  find-rc)    [ $# -eq 2 ] || die "usage: find-rc <vX.Y.Z> <commit>"; find_rc "$@" ;;
  copy)       [ $# -eq 2 ] || die "usage: copy <source-ref> <target-ref>"; copy "$@" ;;
  *) die "usage: promote-images.sh login|find-build|find-rc|copy ..." ;;
esac
