#!/usr/bin/env bash
# Exercise the actual installer against a local, checksummed release fixture.
set -euo pipefail
cd /src
mkdir -p /tmp/libsh-assets /tmp/libsh-download
tar -czf /tmp/libsh-assets/libsh-lib-0.0.0-test.tar.gz lib
tar -czf /tmp/libsh-assets/libsh-ext-secret-0.0.0-test.tar.gz extensions/libsecret.sh
(
  cd /tmp/libsh-assets
  sha256sum ./*.tar.gz | sed 's|  ./|  |' >CHECKSUMS_SHA256.txt
)
cat >/tmp/libsh-download/curl <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 8 && $1 == -fsSL && $2 == --connect-timeout && $4 == --max-time && $6 == -o ]]
case $8 in
  https://github.com/adnoctem/libsh/releases/download/v0.0.0-test/CHECKSUMS_SHA256.txt | \
    https://github.com/adnoctem/libsh/releases/download/v0.0.0-test/libsh-lib-0.0.0-test.tar.gz | \
    https://github.com/adnoctem/libsh/releases/download/v0.0.0-test/libsh-ext-secret-0.0.0-test.tar.gz)
    cp "/tmp/libsh-assets/${8##*/}" "$7"
    ;;
  *) exit 1 ;;
esac
CURL
chmod +x /tmp/libsh-download/curl
umask 077
PATH="/tmp/libsh-download:$PATH" LIBSH_VERSION=0.0.0-test \
  LIBSH_NO_MODIFY_PROFILE=1 LIBSH_INSTALL_DIR=/usr/local/lib/libsh bash bin/install --extensions secret
