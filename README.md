# Symphony Docker Bundle

This package is a fuller containerized setup for running OpenAI Symphony with Codex, Linear, Git, SSH, and GitHub CLI support in one place.

## Upstream reference

The upstream OpenAI Symphony repository is:

- <https://github.com/openai/symphony>

## What this bundle fixes compared with a minimal draft

1. Installs GitHub CLI (`gh`), which Symphony's `.codex/skills/push` and `.codex/skills/land` treat as a prerequisite.
2. Installs `mise`, because Symphony's `.codex/worktree_init.sh` requires it.
3. Avoids the common mounted-`known_hosts` write problem by copying SSH files from read-only mounts into writable runtime paths under `/root/.ssh`.
4. Supports either mounted Codex/GitHub config directories or token-based non-interactive login at container startup.
5. Adds a doctor script and a healthcheck so you can verify the container.
6. Uses a direct `4000:4000` port map instead of an extra socat proxy.

## Directory layout

```text
.
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── README.md
├── config/
│   └── WORKFLOW.docker.md.example
├── data/
│   ├── logs/
│   └── workspaces/
├── scripts/
│   ├── docker-entrypoint.sh
│   ├── doctor.sh
│   └── healthcheck.sh
└── secrets/
    ├── codex/
    ├── gh/
    └── ssh/
        └── config.example
```

## Quick start

1. Copy this directory somewhere convenient.
2. Create your runtime files:

   ```bash
   cp .env.example .env
   cp config/WORKFLOW.docker.md.example config/WORKFLOW.docker.md
   cp secrets/ssh/config.example secrets/ssh/config
   ```

3. Edit `.env`:
   - `LINEAR_API_KEY` = your Linear personal API key
   - `SOURCE_REPO_URL` = repo Symphony should clone into per-ticket workspaces
   - optionally `OPENAI_API_KEY`
   - optionally `GITHUB_TOKEN` or `GH_TOKEN`

4. Edit `config/WORKFLOW.docker.md`:
   - set `tracker.project_slug`
   - adjust the workflow instructions below the YAML front matter if needed

5. Put your SSH private key at:

   ```text
   secrets/ssh/id_ed25519
   ```

   Then fix local permissions before first run:

   ```bash
   chmod 600 secrets/ssh/id_ed25519
   chmod 600 secrets/ssh/config
   ```

6. Seed `known_hosts` from the host:

   ```bash
   ssh-keyscan -t rsa,ecdsa,ed25519 github.com > secrets/ssh/known_hosts
   chmod 644 secrets/ssh/known_hosts
   ```

7. Build and start:

   ```bash
   docker compose build
   docker compose up -d
   ```

8. Inspect logs:

   ```bash
   docker compose logs -f symphony
   ```

9. Run the bundled verification script:

   ```bash
   ./verify_symphony_docker.sh
   ```

   This is the recommended first verification pass after `docker compose up -d`.

## How `.codex` should be set up

You have three common approaches.

### Approach A: token login only

If you set `OPENAI_API_KEY` in `.env`, the entrypoint can run:

```bash
codex login --with-api-key
```

That is the simplest non-interactive setup. In this mode, `secrets/codex/` can stay empty.

### Approach B: seed a Codex config directory

If you already have a working Codex login on the host, copy the contents of your existing `~/.codex/` into:

```text
secrets/codex/
```

At startup, the entrypoint can copy that directory into `/root/.codex` inside the container. This is better than bind-mounting a single file when tools may need writable runtime state.

### Approach C: directly persist `/root/.codex`

If you want Codex session/history/config state to persist across container restarts, you can directly mount a writable local directory:

```yaml
# Optionally, you can mount a local .codex config for persistence
# - ./volumes/.codex:/root/.codex
```

This is the simplest approach when the container runs as `root` and you want local Codex history/session files to be retained.

On startup, the entrypoint seeds any missing files from the upstream `/opt/symphony/.codex` tree into `/root/.codex`, then applies any files from `secrets/codex/` on top.

### Why copy instead of direct read-only bind mount?

Several CLI tools try to update auth/session files in place. A read-only bind mount or a file mapped from a different filesystem can trigger failures or odd rename/link behavior. Copying to a writable in-container path is safer.

## How GitHub CLI (`gh`) auth is handled

Again there are two supported approaches.

### Approach A: token via env

Set either `GH_TOKEN` or `GITHUB_TOKEN` in `.env`.

At startup the entrypoint runs:

```bash
gh auth login --with-token
gh auth setup-git
```

### Approach B: mount existing `gh` config

If your host already has a working `gh` login, copy its config directory into:

```text
secrets/gh/
```

Typical host location:
- Linux/macOS: `~/.config/gh/`

Then the entrypoint syncs it to `/root/.config/gh` in the container.

## How SSH is handled safely

Recommended files under `secrets/ssh/`:
- `id_ed25519`
- `known_hosts`
- `config`

The container entrypoint copies them into `/root/.ssh`, fixes permissions, and adds GitHub host keys if needed.

Recommended SSH config:

```sshconfig
Host github.com
  HostName github.com
  User git
  IdentityFile /root/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking yes
  UserKnownHostsFile /root/.ssh/known_hosts
```

Important permission rules:
- private key: `600`
- ssh config: `600`
- `.ssh/` dir: `700`
- known_hosts: `644`

This avoids common SSH errors such as:
- `Bad owner or permissions on /root/.ssh/config`
- cross-device rename problems while updating `known_hosts`

## Detailed verification and manual checks

If `./verify_symphony_docker.sh` reports warnings or failures, use the checks in
this section to inspect specific areas manually.

Enter the container:

```bash
docker compose exec symphony bash
```

### Test 1: verify tools exist

```bash
codex --version
gh --version
git --version
mise --version
elixir --version
```

### Test 2: verify Codex login

```bash
codex login status
```

### Test 3: verify GitHub CLI login

```bash
gh auth status
```

### Test 4: verify SSH to GitHub

```bash
ssh -T git@github.com
```

Expected success usually looks like:

```text
Hi USERNAME! You've successfully authenticated, but GitHub does not provide shell access.
```

### Test 5: verify Git remote access

```bash
git ls-remote git@github.com:YOUR_ORG/YOUR_REPO.git | head
```

### Test 6: verify `gh` can see the repo

```bash
gh repo view YOUR_ORG/YOUR_REPO
```

### Test 7: verify Symphony workflow file is visible

```bash
ls -l /config/WORKFLOW.docker.md
sed -n '1,80p' /config/WORKFLOW.docker.md
```

### Test 8: run the bundled doctor script

```bash
doctor.sh
```

## How to configure the workflow file

Edit `config/WORKFLOW.docker.md`.

At minimum, set:
- `tracker.project_slug`
- the Markdown task instructions below the YAML front matter

Notes:
- Symphony's default example assumes Linear states like `Rework`, `Human Review`, and `Merging`. If your Linear workflow does not have those states, either add them in Linear or rewrite the workflow prompt/state map accordingly.
- If your target repository uses `mise.toml` or `.tool-versions`, this bundle's example workflow tries `mise trust` and `mise install` in `after_create`.

## How to use a private repository

Use an SSH URL in `.env`:

```bash
SOURCE_REPO_URL=git@github.com:YOUR_ORG/YOUR_PRIVATE_REPO.git
```

Then make sure:
- the SSH key has repo access
- `ssh -T git@github.com` succeeds
- `git ls-remote` on the repo succeeds
- `gh repo view YOUR_ORG/YOUR_PRIVATE_REPO` succeeds if you want PR workflows

## Common problems and fixes

### 1. `gh: command not found`

Cause: image did not install GitHub CLI.

Fix: this bundle installs `gh` in the Dockerfile.

### 2. `mise: command not found`

Cause: minimal images skip it.

Fix: this bundle installs `mise` because Symphony's worktree init helper uses it.

### 3. `Bad owner or permissions on /root/.ssh/config`

Fix:

```bash
chmod 700 secrets/ssh
chmod 600 secrets/ssh/config secrets/ssh/id_ed25519
chmod 644 secrets/ssh/known_hosts
```

### 4. `hostfile_replace_entries ... Invalid cross-device link`

Cause: SSH tried to rewrite a bind-mounted `known_hosts` file.

Fix: this bundle copies SSH files into a writable in-container `.ssh` directory instead of editing the bind mount in place.

### 5. `codex login status` fails

Cause: no API key and no valid `.codex` config.

Fix:
- set `OPENAI_API_KEY` in `.env`, or
- seed `secrets/codex/`, or
- directly mount `./volumes/.codex:/root/.codex`

### 6. `gh auth status` fails

Cause: no token and no valid `gh` config.

Fix:
- set `GH_TOKEN` or `GITHUB_TOKEN`, or
- seed `secrets/gh/`

### 7. `ssh -T git@github.com` fails

Cause: missing key, bad permissions, missing host key, or the SSH key has no repo access.

Fix:
- ensure `secrets/ssh/id_ed25519` exists
- ensure permissions are correct
- regenerate `known_hosts`
- verify the public key is added to GitHub

## Suggested Docker Compose mount note

If you want Codex state persistence, you can keep this commented line in `docker-compose.yml` as a documented option:

```yaml
# Optionally, you can mount a local .codex config for persistence
# - ./volumes/.codex:/root/.codex
```

## Minimal verification flow

From the host:

```bash
docker compose build
docker compose up -d
docker compose logs -f symphony
./verify_symphony_docker.sh
```

If you need to debug individual checks, enter the container:

```bash
docker compose exec symphony bash
```

Then verify in the container:

```bash
codex login status
gh auth status
ssh -T git@github.com
git ls-remote git@github.com:YOUR_ORG/YOUR_REPO.git | head
```
