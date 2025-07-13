# Dockerfile to create a self-contained environment for running Neovim plugin tests.
#
# Build command:
#   docker build -t aiignore-tester .
#
# Run command:
#   docker run --rm aiignore-tester

FROM ubuntu:24.04

ARG NVIM_VERSION=v0.11.3
ARG NVIM_PKG=nvim-linux-x86_64.tar.gz
ARG NVIM_URL=https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_PKG}

RUN DEBIAN_FRONTEND=noninteractive \
  apt-get update \
  && apt-get install -y --no-install-recommends \
     git curl tar ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN curl -LO ${NVIM_URL} \
 && rm -rf /opt/nvim \
 && tar -C /opt -xzf ${NVIM_PKG} \
 && mv /opt/nvim-* /opt/nvim \
 && rm ${NVIM_PKG}

ENV PATH="/opt/nvim/bin:${PATH}"

ENV NVIM_PACK_DIR=/root/.local/share/nvim/site/pack/vendor/start
RUN git clone --depth 1 https://github.com/nvim-lua/plenary.nvim "$NVIM_PACK_DIR/plenary.nvim"

WORKDIR /usr/src/aiignore.nvim
COPY lua lua
COPY tests tests

CMD [ \
  "nvim", \
  "--headless", \
  "-c", "PlenaryBustedDirectory tests/", \
  "-c", "qa!" \
]
