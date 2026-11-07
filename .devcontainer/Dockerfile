FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# OCaml toolchain (opam) and the system libraries Dream links against.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      opam build-essential pkg-config m4 libev-dev libssl-dev libgmp-dev libsqlite3-dev sqlite3 \
 && rm -rf /var/lib/apt/lists/*

USER vscode
ARG OCAML_VERSION=5.3.0
RUN opam init --disable-sandboxing --bare -y \
 && opam switch create default ${OCAML_VERSION} -y \
 && opam install -y dune ocaml-lsp-server ocamlformat utop \
 && opam clean -a -c -s --logs \
 && echo 'eval $(opam env --switch=default)' >> ~/.bashrc \
 && echo 'eval $(opam env --switch=default)' >> ~/.profile
ENV OPAMSWITCH=default
USER root
