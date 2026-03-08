FROM hexpm/elixir:1.19.0-erlang-26.2.2-debian-bookworm-20251117

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MIX_ENV=prod \
    MISE_DATA_DIR=/opt/mise \
    MISE_CACHE_DIR=/opt/mise/cache \
    PATH=/root/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    git-lfs \
    openssh-client \
    build-essential \
    inotify-tools \
    jq \
    tini \
    make \
    procps \
    rsync \
    unzip \
    zip \
    ripgrep \
    less \
    file \
    python3 \
    python3-pip \
    gnupg \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
 && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get update && apt-get install -y --no-install-recommends nodejs gh \
 && npm i -g @openai/codex \
 && curl https://mise.run | sh \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 https://github.com/openai/symphony.git

WORKDIR /opt/symphony/elixir
RUN mix local.hex --force \
 && mix local.rebar --force \
 && mix deps.get \
 && mix build

RUN mkdir -p /data/workspaces /data/logs /config /secrets/ssh /secrets/gh /secrets/codex \
 && mkdir -p /root/.ssh /root/.codex /root/.config/gh \
 && chmod 700 /root/.ssh

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/doctor.sh /usr/local/bin/doctor.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY scripts/tracker_kind_linear.sh /usr/local/bin/tracker_kind_linear.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/doctor.sh /usr/local/bin/healthcheck.sh /usr/local/bin/tracker_kind_linear.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=5 CMD /usr/local/bin/healthcheck.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
