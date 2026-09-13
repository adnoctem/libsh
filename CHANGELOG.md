## [0.6.0](https://github.com/adnoctem/libsh/compare/v0.5.0...v0.6.0) (2026-09-13)

### ⚠ BREAKING CHANGES

* **lib:** Remove color and timed logging wrappers in favor of
intent emitters. Intent output includes UTC timestamps; warnings use
stderr. Raw print, plain, and write remain available.
* **lib:** venv creation now refuses existing incomplete paths
instead of attempting to repair them.
* **lib:** rename lib::net::is_ipv4 and lib::net::is_ipv6 to
lib::net::ipv4_validate and lib::net::ipv6_validate.
* **lib:** move os::ensure_existence and os::ensure_directory
to fs::ensure_existence and fs::ensure_directory.
* **lib:** add shared primitives for phase two
* **lib:** Module paths and public namespaces have changed.
Source lib/lib.sh for core and call lib::load_extensions for explicitly
installed addons. The libtree default layout is now
scripts/libsh/{lib,extensions}.

### Features

* **lib:** add filesystem hashing and comparison helpers ([c99dbe8](https://github.com/adnoctem/libsh/commit/c99dbe8e3e09eee59e22a446a7f60bd135156a86))
* **lib:** add networking parsers and probes ([15600d6](https://github.com/adnoctem/libsh/commit/15600d60f4dfce9e5582e9d9f41e0145bebdb61d))
* **lib:** add OS inspection and account management ([c9de769](https://github.com/adnoctem/libsh/commit/c9de769530764ba0737d2c191a74b43cbd37662b))
* **lib:** add shared primitives for phase two ([f5d0acd](https://github.com/adnoctem/libsh/commit/f5d0acd192b4df9b3318b5f9c3a18c9cb60df25d))
* **lib:** add staged file editing and file logging ([d0d5c8c](https://github.com/adnoctem/libsh/commit/d0d5c8c7182ccb9790c4aa5a4cc795a17df3dd3d))
* **lib:** complete phase 2 extensions and API reference ([8e2a727](https://github.com/adnoctem/libsh/commit/8e2a72784471065500a2b5d8fcdb54227b2c89ff))
* **lib:** introduce intent-based logging and shared UTC timestamps ([b297349](https://github.com/adnoctem/libsh/commit/b297349d8453590eb43ce045601b0223faff47f3))
* **lib:** support environment preservation in root_exec ([373d255](https://github.com/adnoctem/libsh/commit/373d25517d8a55bdb8e82c7b58d32594030f83c2))

### Bug Fixes

* **lib:** reject recursive directory cycles on macOS ([0c7ae4d](https://github.com/adnoctem/libsh/commit/0c7ae4d11381d4c23825fccab6be07fe2ae50bab))
* **test:** correct macOS metadata assertion and CI terminology ([73c0c3f](https://github.com/adnoctem/libsh/commit/73c0c3fe8391f8d104a6d87ccd884dd0b76a00be))

### Code Refactoring

* **lib:** split core modules from optional extensions ([e76d8bd](https://github.com/adnoctem/libsh/commit/e76d8bd6b934a8a02e98f11da35ae832eb6b56db))

## [0.5.0](https://github.com/adnoctem/libsh/compare/v0.4.0...v0.5.0) (2026-09-11)

### Features

* **bin:** add libman and shared library discovery ([ede0d6b](https://github.com/adnoctem/libsh/commit/ede0d6b930cd12ced65a58a0dd64fbb03c2df8a3))

## [0.4.0](https://github.com/adnoctem/libsh/compare/v0.3.0...v0.4.0) (2026-09-11)

### Features

* **lib:** add lossless secret resolution and returning TCP waits ([0590f23](https://github.com/adnoctem/libsh/commit/0590f23328b56e466b94331745d500cf52112a06))

<!-- markdownlint-disable MD004 MD024 -->
<!-- Generated release sections repeat headings and may use different bullet styles. -->

## [0.3.0](https://github.com/adnoctem/libsh/compare/v0.2.1...v0.3.0) (2026-09-03)

### Features

- **lib:** add XDG path resolution and network adapter/address lookup ([1a7c40f](https://github.com/adnoctem/libsh/commit/1a7c40f1f98d536d817e32bf869af3ef77410d10))

### Bug Fixes

- **test:** force uname in tests instead of relying on the CI platform ([5aa2ba8](https://github.com/adnoctem/libsh/commit/5aa2ba84d4aec48b31bb7ef7e7b6169dc89fa1bf))

## [0.2.1](https://github.com/adnoctem/libsh/compare/v0.2.0...v0.2.1) (2026-09-03)

### Bug Fixes

- **bin:** stop 'install' exiting 1 after a fully successful run ([997293a](https://github.com/adnoctem/libsh/commit/997293a72f3d8a281f10e317686590ea0d584003))

## [0.2.0](https://github.com/adnoctem/libsh/compare/v0.1.1...v0.2.0) (2026-09-03)

### Features

- implement the machine installer and fix the release pipeline ([b256157](https://github.com/adnoctem/libsh/commit/b256157b3b2dbb2442aaafec6c29fd740a7ed5e3))

### Bug Fixes

- **ci:** pass a github-token to bats-core/bats-action ([7383588](https://github.com/adnoctem/libsh/commit/73835884ba374876b330446a589f938d25512dea))
- **config:** stop the prettier hook from formatting vendored submodules ([4861436](https://github.com/adnoctem/libsh/commit/4861436fe7a082af78f3cfef899f8fff227f98b5))
- portable stat/date/wc/script across GNU and BSD, plus macOS bash 3.2 ([ed0c82f](https://github.com/adnoctem/libsh/commit/ed0c82fdb7e0dfeb404dfa10168f4f201932ba41))
- **scripts:** update 'mysql-dump' argument order ([c5a303c](https://github.com/adnoctem/libsh/commit/c5a303c5745d9f905fb17ca55878840f11a6b4de))
- **test:** skip TTY-faking tests on macOS, BSD script can't drive them ([ed38f08](https://github.com/adnoctem/libsh/commit/ed38f084a7a08eaa3b52f901002237ebf8252ca8))
- update invalid variable assignment for `tar-archive` script ([086121d](https://github.com/adnoctem/libsh/commit/086121d9134aab07ce2c9092802bad18f86985f3))
