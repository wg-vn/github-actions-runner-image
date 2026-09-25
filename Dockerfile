FROM buildpack-deps:26.04

# catthehacker/docker_images' act recipe, which publishes no Ubuntu 26.04 image yet.
ARG CATTHEHACKER_REF=e2f8efe464c82732f78e967ee709c00b6af53643
ARG NODE_VERSION="20 24"
ENV DEBIAN_FRONTEND=noninteractive

SHELL [ "/bin/bash", "--login", "-e", "-o", "pipefail", "-c" ]
WORKDIR /tmp

RUN mkdir -p /imagegeneration/installers && \
    curl -fsSL "https://github.com/catthehacker/docker_images/archive/${CATTHEHACKER_REF}.tar.gz" | \
      tar -xz --strip-components=4 -C /imagegeneration/installers "docker_images-${CATTHEHACKER_REF}/linux/ubuntu/scripts" && \
    # apt 3 has no apt-key (act.sh also installs the key into trusted.gpg.d), and
    # Microsoft signs its 26.04 repo with the 2025 key rather than microsoft.asc.
    sed -i -e '/apt-key add/d' \
      -e 's|wget -q https://packages.microsoft.com/keys/microsoft.asc|wget -qO microsoft.asc https://packages.microsoft.com/keys/microsoft-2025.asc|' \
      /imagegeneration/installers/act.sh && \
    bash /imagegeneration/installers/act.sh

# catthehacker's build turns /etc/environment into image ENV after act.sh; these are its values.
ENV IMAGE_OS=ubuntu26 ImageOS=ubuntu26 LSB_RELEASE=26.04 LSB_OS_VERSION=2604 \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache RUN_TOOL_CACHE=/opt/hostedtoolcache \
    ACT_TOOLSDIRECTORY=/opt/acttoolcache DEPLOYMENT_BASEPATH=/opt/runner \
    USER=root RUNNER_USER=root
RUN ln -s /opt/acttoolcache/node/24.*/x64/bin/* /usr/local/bin/

# gh from GitHub's own apt repo; Ubuntu's package lags far behind the hosted runner's.
RUN mkdir -p -m 755 /etc/apt/keyrings && \
    wget -qO /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && \
    apt-get install -y mysql-server gh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
