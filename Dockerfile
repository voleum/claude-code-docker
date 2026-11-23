# syntax=docker/dockerfile:1

# ---------- base: only what Claude Code needs to start ----------
FROM alpine:latest AS base

# apk package version (e.g. 2.1.330-r1). Empty = newest in the channel.
ARG CLAUDE_CODE_VERSION=""

RUN apk upgrade --no-cache \
 && wget -qO /etc/apk/keys/claude-code.rsa.pub https://downloads.claude.ai/keys/claude-code.rsa.pub \
 && echo "395759c1f7449ef4cdef305a42e820f3c766d6090d142634ebdb049f113168b6  /etc/apk/keys/claude-code.rsa.pub" | sha256sum -c \
 && echo "https://downloads.claude.ai/claude-code/apk/latest" >> /etc/apk/repositories \
 && apk add --no-cache \
      bash ca-certificates libgcc libstdc++ \
      "claude-code${CLAUDE_CODE_VERSION:+=$CLAUDE_CODE_VERSION}" \
 && adduser -D -u 1000 claude \
 && mkdir -p /workspace \
 && chown claude:claude /workspace

# The image is the update channel: Claude Code cannot upgrade itself here
ENV DISABLE_UPDATES=1

USER claude
WORKDIR /workspace
ENTRYPOINT ["claude"]

# ---------- full: base + everyday tools ----------
FROM base AS full

USER root
RUN apk add --no-cache \
      git jq patch procps-ng tzdata unzip xz
USER claude
