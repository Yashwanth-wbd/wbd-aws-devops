#!/usr/bin/env bash
# Publishes a frontend build as a new release folder and switches CloudFront to it.
#
#   deploy-frontend.sh <dist-dir> <bucket> <release> <kvs-arn> <ssm-prefix>   -> prints the previous release
#   deploy-frontend.sh switch <kvs-arn> <release>                              -> rollback / re-point only
#
# Files go to s3://<bucket>/releases/<release>/. The CloudFront Function serves the folder named
# in key current_release of the key value store, so the switch is atomic and old releases stay
# available for rollback. config.json carries the public per-environment Okta settings, so the
# same build runs in every environment.
set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }

kvs_get() {
  aws cloudfront-keyvaluestore get-key --kvs-arn "$1" --key current_release --query Value --output text 2>/dev/null || echo "none"
}

kvs_put() {
  local etag
  etag=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn "$1" --query ETag --output text)
  aws cloudfront-keyvaluestore put-key --kvs-arn "$1" --key current_release --value "$2" --if-match "$etag" > /dev/null
  echo "current_release -> $2" >&2
}

if [ "${1:-}" = "switch" ]; then
  [ $# -eq 3 ] || die "usage: deploy-frontend.sh switch <kvs-arn> <release>"
  kvs_put "$2" "$3"
  exit 0
fi

[ $# -eq 5 ] || die "usage: deploy-frontend.sh <dist-dir> <bucket> <release> <kvs-arn> <ssm-prefix>"
dist="$1" bucket="$2" release="$3" kvs="$4" ssm="$5"
[ -f "$dist/index.html" ] || die "$dist/index.html not found - is this a frontend build?"
dest="s3://${bucket}/releases/${release}"

param() { aws ssm get-parameter --name "${ssm}/okta/$1" --query Parameter.Value --output text; }
jq -n --arg issuer "$(param issuer)" --arg client "$(param client_id)" --arg aud "$(param audience)" --arg rel "$release" \
  '{ oktaIssuer: $issuer, oktaClientId: $client, oktaAudience: $aud, apiBaseUrl: "/api", release: $rel }' > "$dist/config.json"

# Hashed assets are cached for a year; index.html and config.json are always revalidated.
aws s3 sync "$dist" "$dest" --delete --only-show-errors \
  --exclude index.html --exclude config.json --cache-control "public,max-age=31536000,immutable"
aws s3 cp "$dist/index.html" "$dest/index.html" --only-show-errors --cache-control "no-cache"
aws s3 cp "$dist/config.json" "$dest/config.json" --only-show-errors --cache-control "no-cache"
echo "Uploaded $(find "$dist" -type f | wc -l) files to $dest" >&2

previous=$(kvs_get "$kvs")
kvs_put "$kvs" "$release"
echo "$previous"
