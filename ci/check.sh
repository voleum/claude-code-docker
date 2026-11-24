#!/bin/sh
# Decide whether a new image has to be built.
# Requires: curl, tar, and docker with buildx. For a private repository a
# docker login has to be done first.
#   IMAGE      - image name without a tag, e.g. user/claude-code
#   FORCE      - 1 or true: build even if the version tag is already published
#   PLATFORMS  - defaults to linux/amd64,linux/arm64
#
# Prints the decision. In GitHub Actions it also sets the step outputs
#   build    - true or false
#   version  - apk package version to build, e.g. 2.1.330-r1
set -eu

: "${IMAGE:?IMAGE is not set}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
FORCE="${FORCE:-}"

# An unset secret in the workflow leaves an image name like "/claude-code"
case "$IMAGE" in
  /* | */)
    echo "IMAGE is not a valid image name: '$IMAGE'" >&2
    exit 1
    ;;
esac

# Report the decision and stop
finish() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "build=$1" >> "$GITHUB_OUTPUT"
    echo "version=${APK_VER:-}" >> "$GITHUB_OUTPUT"
  fi
  exit 0
}

# 1. Which version is in the apk "latest" channel, for every target platform
APK_REPO=https://downloads.claude.ai/claude-code/apk/latest

# Newest claude-code version in the apk index of one architecture
apk_version() {
  index=$(mktemp)
  if ! curl -fsSL --retry 3 -o "$index" "$APK_REPO/$1/APKINDEX.tar.gz"; then
    rm -f "$index"
    echo "Cannot download the apk index for $1" >&2
    return 1
  fi
  tar -xzO -f "$index" APKINDEX \
    | awk -F: '$1 == "P" { p = $2 } $1 == "V" && p == "claude-code" { print $2 }' \
    | sort -V | tail -n 1
  rm -f "$index"
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
    if [ "$FORCE" = "1" ] || [ "$FORCE" = "true" ]; then
      echo "Package versions differ between architectures, a forced build is not possible now" >&2
      exit 1
    fi
    echo "Package versions differ between architectures, waiting for the next run"
    finish false
  fi
  APK_VER=$v
done

# 2. Already published? Check the tag with the full apk version, so a
#    repackaged release (-r2) is rebuilt too. The -full variant is pushed
#    last, so a build that failed halfway is retried on the next run.
if [ "$FORCE" = "1" ] || [ "$FORCE" = "true" ]; then
  echo "Forced rebuild of $APK_VER"
  finish true
fi

# The lookup goes through docker, so it uses the current login and works
# for public and private repositories alike.
if out=$(docker buildx imagetools inspect "$IMAGE:$APK_VER-full" 2>&1); then
  echo "$IMAGE:$APK_VER-full already exists, nothing to build"
  finish false
fi

# Only a plain "not found" means the tag is missing. Anything else (no
# access, registry or network trouble) must not trigger a rebuild.
case "$out" in
  *": not found"*)
    echo "$IMAGE:$APK_VER-full is not published yet, build needed"
    finish true
    ;;
  *)
    echo "Cannot check $IMAGE:$APK_VER-full in the registry:" >&2
    echo "$out" >&2
    exit 1
    ;;
esac
