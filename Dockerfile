FROM ubuntu:24.04@sha256:cd1dba651b3080c3686ecf4e3c4220f026b521fb76978881737d24f200828b2b

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    gnupg \
    jq \
    unzip \
    iptables \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y git nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscli.zip" \
    && unzip /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscli.zip

RUN curl -fsSL https://tailscale.com/install.sh | sh

ARG OPENCLAW_VERSION=2026.2.6-3
RUN npm install -g openclaw@${OPENCLAW_VERSION}

RUN useradd -m -s /bin/bash openclaw

RUN mkdir -p /home/openclaw/.openclaw/transforms \
    && mkdir -p /home/openclaw/clawd \
    && chown -R openclaw:openclaw /home/openclaw

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 18789

ENTRYPOINT ["/entrypoint.sh"]
