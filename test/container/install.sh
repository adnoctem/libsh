#!/usr/bin/env bash
# Exercise the actual installer against a local, checksummed release fixture.
set -euo pipefail
cd /src
mkdir -p /tmp/libsh-assets /tmp/libsh-download
tar -czf /tmp/libsh-assets/libsh-lib-0.0.0-test.tar.gz lib
(
  cd /tmp/libsh-assets
  sha256sum libsh-lib-0.0.0-test.tar.gz >CHECKSUMS_SHA256.txt
)
cat >/tmp/libsh-download/curl <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 4 && $1 == -fsSL && $2 == -o ]]
case $4 in
  https://github.com/adnoctem/libsh/releases/download/v0.0.0-test/CHECKSUMS_SHA256.txt | \
    https://github.com/adnoctem/libsh/releases/download/v0.0.0-test/libsh-lib-0.0.0-test.tar.gz)
    cp "/tmp/libsh-assets/${4##*/}" "$3"
    ;;
  *) exit 1 ;;
esac
CURL
chmod +x /tmp/libsh-download/curl
PATH="/tmp/libsh-download:$PATH" LIBSH_VERSION=0.0.0-test \
  LIBSH_NO_MODIFY_PROFILE=1 LIBSH_INSTALL_DIR=/usr/local/lib/libsh bash bin/install
