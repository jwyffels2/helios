#podman build -t helios-build -f ./build.dockerfile .
FROM ubuntu:plucky

ENV ALIRE_VERSION=2.1.0
ENV GPRBUILD_VERSION=25.0.1
ENV RISC_COMPILER_VERSION=14.2.1


RUN apt-get update && \
    apt-get install \
    build-essential=12.12ubuntu1 \
    git\
    ca-certificates\
    curl\
    unzip\
    -y\
    && rm -rf /var/lib/apt/lists/*
# Download Alire ZIP
RUN curl -L -o /tmp/alr.zip \
    "https://github.com/alire-project/alire/releases/download/v${ALIRE_VERSION}/alr-${ALIRE_VERSION}-bin-x86_64-linux.zip" \
 && unzip -j /tmp/alr.zip -d /usr/bin \
 && chmod +x /usr/bin/alr

# For some rreason Alire will not compile with regular user permissions so bad practice be damned
#USER ubuntu
#WORKDIR /home/ubuntu
#ENV HOME=/home/ubuntu

RUN alr index --update-all && alr toolchain --select gnat_riscv64_elf="${RISC_COMPILER_VERSION}" gprbuild="${GPRBUILD_VERSION}"

# Resolve the actual toolchain dir once and give it a stable path
RUN set -eux; \
    dir="$(find "$HOME/.local/share/alire/toolchains" -maxdepth 1 -mindepth 1 -name "gnat_riscv64_elf_${RISC_COMPILER_VERSION}*" -print -quit)"; \
    [ -n "$dir" ] || { echo "No toolchain found for ${RISC_COMPILER_VERSION}"; exit 1; }; \
    ln -s "$dir" /opt/riscv

# Persist PATH for all subsequent layers and at runtime
ENV PATH="/opt/riscv/bin:${PATH}"
