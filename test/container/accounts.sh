#!/usr/bin/env bash
# Real account/ownership changes belong only in a disposable test container.
set -euo pipefail
[[ $EUID == 0 && -e /.dockerenv && -d /opt/libsh-test ]] || exit 2

# shellcheck source=lib/lib.sh
source /usr/local/lib/libsh/lib.sh
test_accounts_dir=$(mktemp -d)
trap 'rm -rf "$test_accounts_dir"' EXIT
trap 'exit 1' INT TERM

lib::os::group_ensure libsh_primary --id 15001
lib::os::group_ensure libsh_primary --id 15555
[[ $(getent group libsh_primary) == libsh_primary:x:15001:* ]]
lib::os::group_ensure libsh_extra --id 15002
lib::os::group_ensure libsh_more --id 15003
lib::os::group_ensure libsh_service --system
lib::os::user_ensure libsh_service --system --group libsh_service
lib::os::user_exists libsh_service

lib::os::user_ensure libsh_person --id 16001 --group libsh_primary \
  --append-groups libsh_extra --home "$test_accounts_dir/old-home"
lib::os::user_ensure libsh_person --id 17000 --home /different
[[ $(id -u libsh_person) == 16001 ]]
[[ $(getent passwd libsh_person) == *":$test_accounts_dir/old-home:"* ]]
mkdir -p "$test_accounts_dir/old-home"
touch "$test_accounts_dir/old-home/retained"

lib::os::user_update libsh_person --id 16011 --append-groups libsh_more \
  --home "$test_accounts_dir/new-home"
[[ $(id -u libsh_person) == 16011 ]]
test_accounts_groups=" $(id -G libsh_person) "
[[ $test_accounts_groups == *' 15002 '* && $test_accounts_groups == *' 15003 '* ]]
[[ $(getent passwd libsh_person) == *":$test_accounts_dir/new-home:"* ]]
[[ -f $test_accounts_dir/old-home/retained && ! -e $test_accounts_dir/new-home ]]
lib::os::group_update libsh_primary --id 15011
[[ $(getent group libsh_primary) == libsh_primary:x:15011:* ]]

mkdir -p "$test_accounts_dir/tree/sub" "$test_accounts_dir/outside"
touch "$test_accounts_dir/tree/.hidden" "$test_accounts_dir/tree/sub/file" "$test_accounts_dir/outside/file"
ln -s "$test_accounts_dir/outside" "$test_accounts_dir/tree/link"
lib::fs::owner_set "$test_accounts_dir/tree/.hidden" libsh_person:libsh_primary
[[ $(lib::fs::owner_get "$test_accounts_dir/tree/.hidden" uid) == 16011 ]]
[[ $(lib::fs::owner_get "$test_accounts_dir/tree/.hidden" gid) == 15011 ]]

lib::os::recursive_configure "$test_accounts_dir/tree" -u libsh_person -g libsh_primary -f 640 -d 750 -n
[[ $(stat -c %u "$test_accounts_dir/tree/link") == 16011 ]]
[[ $(stat -c %u "$test_accounts_dir/outside/file") == 0 ]]
[[ $(stat -c %a "$test_accounts_dir/tree/sub/file") == 640 ]]
lib::os::recursive_configure "$test_accounts_dir/tree" -u libsh_person -g libsh_primary -f 644
[[ $(stat -c %u "$test_accounts_dir/outside/file") == 16011 ]]
[[ $(stat -c %a "$test_accounts_dir/outside/file") == 644 ]]

[[ $(lib::os::boot_time) -gt 0 && $(lib::os::memory total) -gt 0 ]]
[[ $(lib::os::metadata --id) == debian ]]
truncate -s 1048576 "$test_accounts_dir/disk.img"
[[ $(lib::os::disk_capacity "$test_accounts_dir/disk.img") == 1048576 ]]
printf 'Account and ownership integration passed with Bash %s.\n' "$BASH_VERSION"
