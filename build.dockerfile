FROM ubuntu:plucky

RUN apt-get update && \
    apt-get install \
    alire=1.2.1-2build1 \
    build-essential=12.12ubuntu1 \
    git\
    ca-certificates\
    curl\
    -y\
    && rm -rf /var/lib/apt/lists/*

USER ubuntu
WORKDIR /home/ubuntu
ENV HOME=/home/ubuntu

RUN alr --non-interactive toolchain --select
