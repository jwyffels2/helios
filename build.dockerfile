FROM ubuntu:plucky

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
    "https://github.com/alire-project/alire/releases/download/v2.1.0/alr-2.1.0-bin-x86_64-linux.zip" \
 && unzip -j /tmp/alr.zip -d /usr/bin \
 && chmod +x /usr/bin/alr

# For some rreason Alire will not compile with regular user permissions so bad practice be damned
#USER ubuntu
#WORKDIR /home/ubuntu
#ENV HOME=/home/ubuntu

RUN alr index --update-all && alr toolchain --select gnat_riscv64_elf="14.2.1" gprbuild="25.0.1"
