# Claude Code Docker image

A small Alpine-based image with [Claude Code](https://code.claude.com/docs),
rebuilt automatically whenever a new Claude Code version is released.

The image contains no credentials and nothing machine-specific. Authentication
and settings come from the host at run time.

This is an unofficial, community-maintained image. It is not affiliated with
or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic;
Claude Code itself is installed unmodified from Anthropic's official apk
repository and is subject to Anthropic's terms.

## Image variants and tags

| Variant | Contents |
| - | - |
| base | Claude Code and what it needs to start (`bash`, `ca-certificates`, `libgcc`, `libstdc++`) |
| full | base plus `git`, `jq`, `patch`, `procps-ng`, `tzdata`, `unzip`, `xz` |

Both variants are built for `linux/amd64` and `linux/arm64`. Claude Code runs
as user `claude` (UID 1000); the default working directory is `/workspace`.

Tags for Claude Code 2.1.330 (apk package `2.1.330-r1`):

| base | full |
| - | - |
| `latest` | `full` |
| `2` | `2-full` |
| `2.1` | `2.1-full` |
| `2.1.330` | `2.1.330-full` |
| `2.1.330-r1` | `2.1.330-r1-full` |

The `-rN` suffix is the Alpine package revision. It changes when the same
Claude Code version is repackaged.

## Usage

Copy [`compose.example.yaml`](compose.example.yaml) to a place outside your
projects, set the image name in it, and make sure the mounted paths exist:

```sh
mkdir -p ~/.config/claude-docker ~/.claude
cp compose.example.yaml ~/.config/claude-docker/compose.yaml
[ -e ~/.claude.json ] || echo '{}' > ~/.claude.json
```

Then start Claude Code from any project directory:

```sh
docker compose -f ~/.config/claude-docker/compose.yaml run --rm claude
```

### The `dclaude` command

To start Claude Code with a single command, add the `dclaude` function to
your shell config. Paste this into a terminal once; for bash, replace
`~/.zshrc` with `~/.bashrc` in both places.

```sh
cat >> ~/.zshrc <<'EOF'

dclaude() {
  local compose=~/.config/claude-docker/compose.yaml
  if [ "$1" = upgrade ]; then
    docker compose -f "$compose" pull
  else
    docker compose -f "$compose" run --rm claude "$@"
  fi
}
EOF
source ~/.zshrc
```

Run `dclaude` from any project directory. Arguments are passed straight to
Claude Code:

```sh
dclaude                # interactive session
dclaude --version      # any claude option
dclaude -p "explain this repository"
```

The image entrypoint is `claude`. To open a shell in the container instead,
override it:

```sh
docker compose -f ~/.config/claude-docker/compose.yaml run --rm --entrypoint bash claude
```

### Updating the image

```sh
dclaude upgrade
```

This pulls the image named in the compose file. With a moving tag (`full`,
`latest`, `2-full`, `2.1-full`) it downloads the new build once it is on
Docker Hub; with a pinned tag such as `2.1.330-full` there is nothing newer
to pull. The next `dclaude` run uses the new image.

### What the compose file relies on

- **Same project path.** The project is mounted at the same absolute path as
  on the host. Session history, local-scope MCP servers and paths returned by
  an IDE depend on it.
- **Host networking.** Needed to reach services bound to `127.0.0.1` on the
  host, such as the JetBrains MCP server. On Docker Desktop, host networking
  has to be enabled in the settings.
- **Host state.** `~/.claude` and `~/.claude.json` are mounted into the home
  directory of the `claude` user. Do not set `CLAUDE_CONFIG_DIR`: the mounted
  `.claude.json` would be ignored.
- **UID 1000.** On Linux the host user should have UID 1000, otherwise files
  created in the project and in `~/.claude` get a different owner.

### Authentication

The image is meant to be used with a Claude subscription. Do not set
`ANTHROPIC_API_KEY`: with it, usage is billed to the API instead.

On Linux the login stored in `~/.claude` on the host is reused. On macOS the
host keeps credentials in the Keychain, which the container cannot read, so
log in once inside the container.

### Updates

`DISABLE_UPDATES=1` is set in the image: Claude Code cannot upgrade itself
inside the container. A new version arrives with a new image.

## Build pipeline

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs every day at
00:00 UTC and calls [`ci/build.sh`](ci/build.sh), which:

1. reads the current version from the `latest` channel of the official
   Claude Code apk repository;
2. exits if the tag `<apk version>-full` is already on Docker Hub;
3. otherwise builds both variants for both platforms and pushes all tags.

The `-full` tag is pushed last, so a build that fails halfway is retried on
the next run.

### Repository setup

In Settings -> Secrets and variables -> Actions:

| Kind | Name | Value |
| - | - | - |
| secret | `DOCKERHUB_USERNAME` | Docker Hub account name |
| secret | `DOCKERHUB_TOKEN` | Docker Hub access token with Read & Write scope |
| variable | `DOCKERHUB_IMAGE` | optional; defaults to `<DOCKERHUB_USERNAME>/claude-code` |

GitHub disables scheduled workflows in public repositories after 60 days
without repository activity. Re-enable the workflow on the Actions tab when
that happens.

### Forcing a rebuild

To rebuild a version that is already published (for example after changing
the `Dockerfile`), run the workflow manually with `force` enabled: Actions ->
Build Claude Code image -> Run workflow, or

```sh
gh workflow run build.yml -f force=true
```

### Building locally

```sh
docker build --target base -t claude-code:latest .
docker build --target full -t claude-code:full .
docker run --rm claude-code:full --version
```

To pin the Claude Code version, pass the apk package version:

```sh
docker build --target full --build-arg CLAUDE_CODE_VERSION=2.1.330-r1 -t claude-code:full .
```
