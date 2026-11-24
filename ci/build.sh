#!/bin/sh
# Build both image variants and push all tags.
# Requires: docker with buildx and a completed docker login.
#   IMAGE      - image name without a tag, e.g. user/claude-code
#   APK_VER    - apk package version to build, e.g. 2.1.330-r1 (see check.sh)
#   PLATFORMS  - defaults to linux/amd64,linux/arm64
set -eu

: "${IMAGE:?IMAGE is not set}"
: "${APK_VER:?APK_VER is not set}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# Only digits, dots, "-" and "r" (no whitespace or newlines), in the apk shape
case "$APK_VER" in
  *[!0-9.r-]*) valid=false ;;
  *) valid=true ;;
esac
if [ "$valid" != true ] || ! echo "$APK_VER" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$'; then
  echo "APK_VER does not look like an apk version: '$APK_VER'" >&2
  exit 1
fi

VER=${APK_VER%-r*}     # 2.1.330
MINOR=${VER%.*}        # 2.1
MAJOR=${VER%%.*}       # 2

# Multi-arch builder
docker run --privileged --rm tonistiigi/binfmt --install arm64,amd64 >/dev/null
docker buildx create --name ci-builder --use >/dev/null 2>&1 \
  || docker buildx use ci-builder

build() {
  target=$1
  shift
  tags=""
  for t in "$@"; do
    tags="$tags -t $IMAGE:$t"
  done
  # shellcheck disable=SC2086
  docker buildx build --pull \
    --platform "$PLATFORMS" \
    --target "$target" \
    --build-arg "CLAUDE_CODE_VERSION=$APK_VER" \
    $tags --push .
}

# The -full variant goes last: check.sh treats its tag as "published"
build base "$APK_VER" "$VER" "$MINOR" "$MAJOR" latest
build full "$APK_VER-full" "$VER-full" "$MINOR-full" "$MAJOR-full" full

echo "Published: $IMAGE:$APK_VER and $IMAGE:$APK_VER-full"
