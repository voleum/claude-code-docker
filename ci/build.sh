#!/bin/sh
# Build and publish the image. Called from the GitHub Actions workflow.
# Requires: docker with buildx, a completed docker login, and IMAGE.
#   IMAGE      - image name without a tag, e.g. user/claude-code
#   FORCE      - 1 or true: rebuild even if the version tag is already published
#   PLATFORMS  - defaults to linux/amd64,linux/arm64
set -eu

: "${IMAGE:?IMAGE is not set}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
FORCE="${FORCE:-}"

# 1. Which version is currently in the apk "latest" channel
APK_VER=$(docker run --rm alpine:latest sh -ec '
  wget -qO /etc/apk/keys/claude-code.rsa.pub https://downloads.claude.ai/keys/claude-code.rsa.pub
  echo "https://downloads.claude.ai/claude-code/apk/latest" >> /etc/apk/repositories
  apk update -q
  apk search -x claude-code
' | sed 's/^claude-code-//' | sort -V | tail -n 1)

if ! echo "$APK_VER" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$'; then
  echo "Cannot parse the version from apk output: '$APK_VER'" >&2
  exit 1
fi

VER=${APK_VER%-r*}     # 2.1.330
MINOR=${VER%.*}        # 2.1
MAJOR=${VER%%.*}       # 2
echo "Claude Code in the latest channel: $VER (apk $APK_VER)"

# 2. Already published? Check the tag with the full apk version, so a
#    repackaged release (-r2) is rebuilt too. The -full variant is pushed
#    last, so a build that failed halfway is retried on the next run.
if [ "$FORCE" != "1" ] && [ "$FORCE" != "true" ] \
   && docker buildx imagetools inspect "$IMAGE:$APK_VER-full" >/dev/null 2>&1; then
  echo "$IMAGE:$APK_VER-full already exists, nothing to build"
  exit 0
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
