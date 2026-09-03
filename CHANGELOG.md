## [0.2.0](https://github.com/adnoctem/libsh/compare/v0.1.1...v0.2.0) (2026-09-03)

### Features

* implement the machine installer and fix the release pipeline ([b256157](https://github.com/adnoctem/libsh/commit/b256157b3b2dbb2442aaafec6c29fd740a7ed5e3))

### Bug Fixes

* **ci:** pass a github-token to bats-core/bats-action ([7383588](https://github.com/adnoctem/libsh/commit/73835884ba374876b330446a589f938d25512dea))
* **config:** stop the prettier hook from formatting vendored submodules ([4861436](https://github.com/adnoctem/libsh/commit/4861436fe7a082af78f3cfef899f8fff227f98b5))
* portable stat/date/wc/script across GNU and BSD, plus macOS bash 3.2 ([ed0c82f](https://github.com/adnoctem/libsh/commit/ed0c82fdb7e0dfeb404dfa10168f4f201932ba41))
* **scripts:** update 'mysql-dump' argument order ([c5a303c](https://github.com/adnoctem/libsh/commit/c5a303c5745d9f905fb17ca55878840f11a6b4de))
* **test:** skip TTY-faking tests on macOS, BSD script can't drive them ([ed38f08](https://github.com/adnoctem/libsh/commit/ed38f084a7a08eaa3b52f901002237ebf8252ca8))
* update invalid variable assignment for `tar-archive` script ([086121d](https://github.com/adnoctem/libsh/commit/086121d9134aab07ce2c9092802bad18f86985f3))
