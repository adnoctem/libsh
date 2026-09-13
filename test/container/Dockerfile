FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gcc libc6-dev make && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp/bash-build
RUN curl -fsSL https://ftp.gnu.org/gnu/bash/bash-4.0.tar.gz -o bash.tar.gz \
    && echo '9793d394f640a95030c77d5ac989724afe196921956db741bcaf141801c50518  bash.tar.gz' | sha256sum -c - \
    && tar -xzf bash.tar.gz --strip-components=1 \
    && ./configure --prefix=/opt/bash-4.0 --without-bash-malloc \
    && make -j2 && make install
WORKDIR /src
COPY lib lib
COPY extensions extensions
COPY bin/install bin/libman bin/
COPY test/container/install.sh test/container/install.sh
RUN bash test/container/install.sh

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends netcat-openbsd curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /opt/bash-4.0 /opt/bash-4.0
COPY --from=build /usr/local/lib/libsh.libman /usr/local/lib/libsh.libman
COPY bin/install bin/libman /opt/libsh-test/bin/
COPY scripts /opt/libsh-test/scripts
COPY extensions /opt/libsh-test/extensions
COPY test/bin /opt/libsh-test/test/bin
COPY test/bats /opt/libsh-test/test/bats
COPY test/extensions/secret.bats /opt/libsh-test/test/extensions/
COPY test/lib/net.bats test/lib/core.bats test/lib/data.bats test/lib/opt.bats test/lib/os.bats \
    test/lib/fs.bats test/lib/hash.bats test/lib/cmp.bats test/lib/log.bats /opt/libsh-test/test/lib/
COPY test/integration /opt/libsh-test/test/integration
COPY test/container/run.sh /opt/libsh-test/run.sh
RUN ln -s /usr/local/lib/libsh.libman/current/lib /usr/local/lib/libsh \
    && ln -s /usr/local/lib/libsh /opt/libsh-test/lib \
    && mkdir -p /run/secrets/..version \
    && printf '%s\n' '-----BEGIN CERTIFICATE-----' synthetic '-----END CERTIFICATE-----' '' \
       >/run/secrets/..version/certificate \
    && printf 'inaccessible' >/run/secrets/denied \
    && chown root:10001 /run/secrets/..version/certificate \
    && chmod 640 /run/secrets/..version/certificate \
    && chmod 600 /run/secrets/denied \
    && ln -s ..version /run/secrets/..data \
    && ln -s ..data/certificate /run/secrets/certificate
USER 10001:10001
ENTRYPOINT ["bash", "/opt/libsh-test/run.sh"]
