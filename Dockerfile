FROM node:20-bookworm-slim

ARG INSTALL_PHP=false
ARG INSTALL_PYTHON=true
ARG INSTALL_COMPOSER=false

# Always-installed base packages
RUN apt-get update && apt-get install -y \
    git curl sudo ca-certificates \
    ripgrep fd-find jq tree htop unzip zsh \
    iptables ipset dnsutils \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Conditional: Python
RUN if [ "$INSTALL_PYTHON" = "true" ]; then \
    apt-get update && apt-get install -y \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*; \
    fi

# Conditional: PHP
RUN if [ "$INSTALL_PHP" = "true" ]; then \
    apt-get update && apt-get install -y \
    php-cli php-mbstring php-xml php-curl php-zip php-intl \
    && rm -rf /var/lib/apt/lists/*; \
    fi

# Conditional: Composer (requires PHP)
RUN if [ "$INSTALL_COMPOSER" = "true" ]; then \
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer; \
    fi

# UV (Python package manager) — only if Python installed
RUN if [ "$INSTALL_PYTHON" = "true" ]; then \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh || true; \
    fi

RUN npm install -g get-shit-done-cc

ARG USERNAME=node
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupmod --gid $USER_GID $USERNAME \
    && usermod --uid $USER_UID --gid $USER_GID $USERNAME \
    && chown -R $USER_UID:$USER_GID /home/$USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /workspace \
    && mkdir -p /home/$USERNAME/.claude \
    && mkdir -p /home/$USERNAME/.config \
    && chown -R $USER_UID:$USER_GID /workspace /home/$USERNAME

COPY bin/firewall /usr/local/bin/init-firewall
COPY bin/entrypoint /usr/local/bin/entrypoint
COPY bin/update-packages /usr/local/bin/update-packages
RUN chmod 755 /usr/local/bin/init-firewall /usr/local/bin/entrypoint /usr/local/bin/update-packages

WORKDIR /workspace
USER $USERNAME

# Claude Code via native installer (installs to ~/.local/bin/)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Ensure claude is in PATH for all contexts (interactive + non-interactive)
ENV PATH="/home/node/.local/bin:/usr/local/bin:$PATH"

# Plugin installs need TMPDIR on the same filesystem as ~/.claude
ENV TMPDIR="/home/node/.claude/tmp"
RUN mkdir -p /home/node/.claude/tmp

RUN echo 'alias cc="claude --dangerously-skip-permissions"' >> /home/$USERNAME/.bashrc

ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["/bin/bash"]
