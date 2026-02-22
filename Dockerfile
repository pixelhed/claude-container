FROM node:20-bookworm-slim

RUN apt-get update && apt-get install -y \
    git \
    curl \
    sudo \
    ca-certificates \
    ripgrep \
    fd-find \
    jq \
    tree \
    htop \
    unzip \
    zsh \
    iptables \
    ipset \
    dnsutils \
    python3 \
    python3-pip \
    python3-venv \
    php-cli \
    php-mbstring \
    php-xml \
    php-curl \
    php-zip \
    php-intl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh || true
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
COPY bin/update /usr/local/bin/update-packages
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
