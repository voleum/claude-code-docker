#!/bin/sh
# Build and publish the image. Called from the GitHub Actions workflow.
# Requires: docker with buildx, curl, a completed docker login, and IMAGE.
#   IMAGE      - Docker Hub image name without a tag, e.g. user/claude-code
#   FORCE      - 1 or true: rebuild even if the version tag is already published
#   PLATFORMS  - defaults to linux/amd64,linux/arm64
set -eu

: "${IMAGE:?IMAGE is not set}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
FORCE="${FORCE:-}"

# 1. Which version is in the apk "latest" channel, for every target platform
APK_REPO=https://downloads.claude.ai/claude-code/apk/latest

# Newest claude-code version in the apk index of one architecture
apk_version() {
  curl -fsSL --retry 3 "$APK_REPO/$1/APKINDEX.tar.gz" \
    | tar -xzO -f - APKINDEX \
    | awk -F: '$1 == "P" { p = $2 } $1 == "V" && p == "claude-code" { print $2 }' \
    | sort -V | tail -n 1
}

APK_VER=""
for platform in $(echo "$PLATFORMS" | tr ',' ' '); do
  case "$platform" in
    linux/amd64) arch=x86_64 ;;
    linux/arm64) arch=aarch64 ;;
    *) echo "Unsupported platform: $platform" >&2; exit 1 ;;
  esac
  v=$(apk_version "$arch")
  if ! echo "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$'; then
    echo "Cannot read the claude-code version from the apk index for $arch: '$v'" >&2
    exit 1
  fi
  echo "Claude Code in the latest channel for $arch: $v"
  # A release may reach the architectures at different times. Building now
  # would fail for the one that lags behind, so wait for the next run.
  if [ -n "$APK_VER" ] && [ "$v" != "$APK_VER" ]; then
    echo "Package versions differ between architectures, waiting for the next run"
    exit 0
  fi
  APK_VER=$v
done

VER=${APK_VER%-r*}     # 2.1.330
MINOR=${VER%.*}        # 2.1
MAJOR=${VER%%.*}       # 2

# 2. Already published? Check the tag with the full apk version, so a
#    repackaged release (-r2) is rebuilt too. The -full variant is pushed
#    last, so a build that failed halfway is retried on the next run.
#    The repository has to be public for this request to see the tag.
if [ "$FORCE" != "1" ] && [ "$FORCE" != "true" ]; then
  code=$(curl -sS --retry 3 -o /dev/null -w '%{http_code}' \
    "https://hub.docker.com/v2/repositories/${IMAGE#docker.io/}/tags/$APK_VER-full") || code=000
  case "$code" in
    200)
      echo "$IMAGE:$APK_VER-full already exists, nothing to build"
      exit 0
      ;;
    404) ;;
    *)
      echo "Unexpected response from Docker Hub: HTTP $code" >&2
      exit 1
      ;;
  esac
fi

# 3. Multi-arch builder
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

build base "$APK_VER" "$VER" "$MINOR" "$MAJOR" latest
build full "$APK_VER-full" "$VER-full" "$MINOR-full" "$MAJOR-full" full

echo "Published: $IMAGE:$APK_VER and $IMAGE:$APK_VER-full"
