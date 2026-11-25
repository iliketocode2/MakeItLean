# MakeItLean in a container: Lean, the comparator's sandbox (bubblewrap), Python, Node, and `mil`.
# For macOS and Windows (bubblewrap is Linux-only), or to avoid changing the host. See docs/GUIDE.md.
#
#   docker build -t makeitlean .
#   tools/mil-docker mil doctor                  # any command, with the current directory at /work
#
# bubblewrap needs user namespaces inside the container, so run it with
#   --security-opt seccomp=unconfined --security-opt apparmor=unconfined
# (tools/mil-docker does). Nothing else is relaxed: no --privileged.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git bubblewrap python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Node.js (only TypeScript shells need it), pinned
ARG NODE_VERSION=24.13.0
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
      | tar -xJ -C /usr/local --strip-components=1

# a non-root user: files written to the mounted project keep a normal owner
RUN userdel -r ubuntu 2>/dev/null || true; useradd -m -u 1000 mil
# the comparator's sandbox mounts the user's runtime directory; a bare image has none
RUN mkdir -p /run/user/1000 && chown mil:mil /run/user/1000 && chmod 700 /run/user/1000
ENV XDG_RUNTIME_DIR=/run/user/1000
USER mil
ENV PATH=/home/mil/.elan/bin:$PATH
RUN curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
      | sh -s -- -y --default-toolchain none

# the framework checkout (with .git: apps pin it by commit) and `mil`
COPY --chown=mil:mil . /opt/MakeItLean
RUN cd /opt/MakeItLean/cli && lake build \
    && cd /opt/MakeItLean/lean && lake build
ENV MIL_HOME=/opt/MakeItLean
ENV PATH=/opt/MakeItLean/cli/.lake/build/bin:$PATH
RUN git config --global --add safe.directory '*'

WORKDIR /work
CMD ["bash"]
