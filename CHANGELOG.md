# Changelog

## [2.0.0](https://github.com/FelipeFuhr/ffreis-workflows-rust/compare/v1.3.0...v2.0.0) (2026-08-11)


### ⚠ BREAKING CHANGES

* **runner:** callers that rely on the implicit ubuntu-latest default now land on [self-hosted, local] instead (except rust-container.yml, unchanged).

### Features

* **rust:** add integration-coverage workflow + mutation disk-safety guard ([#71](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/71)) ([a9176e8](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/a9176e8abdc63c60617fbfd67f780554287188b8))


### Bug Fixes

* **ci:** mirror missing id-token:write on 5 self-test/CI caller jobs ([#70](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/70)) ([d1453f4](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/d1453f48d844436e20e177f4b15f4c3fd102bea8))
* **ci:** pin own internal CI to ubuntu-latest — public repo can't use self-hosted ([#76](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/76)) ([b83d526](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/b83d5261fe42d74d991c5ee487d1f63f969016b9))
* **ci:** remove redundant standalone scorecards.yml ([#75](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/75)) ([52c02df](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/52c02dfa019b6e92eefe88df3d8545ad10d359c8))
* **examples:** unblock hello self-test (deny/audit/coverage/container) ([#77](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/77)) ([5bbc4dc](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/5bbc4dcbcd5b157dbc602a4ae18b90555f427040))
* **runner:** default the runner input to self-hosted, not ubuntu-latest ([#74](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/74)) ([58205ac](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/58205ac301580a0b8cd31ce74df61e16eba5b237))
* **sonar:** fix dead-code fallback that always used repo-owner org ([#78](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/78)) ([744f232](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/744f2327dfee02a7d1b7bf960613228432593b66))

## [1.3.0](https://github.com/FelipeFuhr/ffreis-workflows-rust/compare/v1.2.1...v1.3.0) (2026-08-07)


### Features

* add self-hosted runner input across remaining rust-*.yml workflows ([#61](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/61)) ([489ab8f](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/489ab8ff64368670d84daf3f0c92f8cf0c152ea8))
* **rust:** add integration-coverage workflow + mutation disk-safety guard ([#71](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/71)) ([a9176e8](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/a9176e8abdc63c60617fbfd67f780554287188b8))
* **rust:** build-wrapper + opt-in affected-only-on-push for constrained runners ([#60](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/60)) ([84f900e](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/84f900e5a218b370e335808984555ccfc8d751e0))
* **rust:** complete PRIVATE_DEPS_TOKEN coverage across cargo workflows ([#69](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/69)) ([231bccb](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/231bccb36090c10d03582460ac99dbadad281ae2))
* **semgrep:** replace Docker-container semgrep-action with native CLI ([#62](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/62)) ([4765527](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/47655272bbc8162af0cf92f2eb2d105120d36ee3))


### Bug Fixes

* **ci:** mirror missing id-token:write on 5 self-test/CI caller jobs ([#70](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/70)) ([d1453f4](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/d1453f48d844436e20e177f4b15f4c3fd102bea8))
* **rust:** cap CARGO_BUILD_JOBS and auto-detect --locked ([#64](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/64)) ([9545e1a](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/9545e1a2c1e7ba88096bae1c5808ac0fab2eb6f1))
* **rust:** extend PRIVATE_DEPS_TOKEN auth to remaining cargo workflows ([#63](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/63)) ([b3fee9b](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/b3fee9bbf0f9b9d6927658bf851955bf797d3bea))
* **rust:** force git-fetch-with-cli for private cargo deps ([#56](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/56)) ([c23893e](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/c23893e5610332226c71b2ec52e6658372c38c1c))
* **rust:** support optional private-deps-token for private cargo git deps ([#54](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/54)) ([f294fd2](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/f294fd2e793093c2e68e65cd57bbc3167fd37388))
* **rust:** support PRIVATE_DEPS_TOKEN in rust-build.yml ([#57](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/57)) ([3e2fcf5](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/3e2fcf57bb07bae6346db12d59579aa06af0250a))

## [1.2.1](https://github.com/FelipeFuhr/ffreis-workflows-rust/compare/v1.2.0...v1.2.1) (2026-06-26)


### Bug Fixes

* **ci:** pin ffreis-workflows-general to v1.7.0 ([#52](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/52)) ([856a88e](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/856a88e6467835aeff011f2868059193e0107b74))

## [1.2.0](https://github.com/FelipeFuhr/ffreis-workflows-rust/compare/v1.1.0...v1.2.0) (2026-06-15)


### Features

* opt-in sccache, nextest, and affected-crate detection ([#33](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/33)) ([7d1a437](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/7d1a437aa234bc743864aa655d93190e35b48d09))


### Bug Fixes

* **grype:** bump workflows-general SHA to prevent self-scan CVEs ([#37](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/37)) ([d783976](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/d783976ad20b5b358e656540dff7e642a179e661))
* resolve SonarQube issues ([#40](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/40)) ([aa543c5](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/aa543c5223c43d3dd55ef26cb7e337bcfe53fd1a))

## [1.1.0](https://github.com/FelipeFuhr/ffreis-workflows-rust/compare/v1.0.0...v1.1.0) (2026-05-24)


### Features

* add rust-proptest reusable workflow + wire into self-test ([#20](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/20)) ([20b3c82](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/20b3c826c18c32b5e64573a0dcef656e679d8d62))
* migrate to platform standards ([#16](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/16)) ([0a0d885](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/0a0d885285ab8cff96c67bce86f7e7970f3bc224))

## 1.0.0 (2026-05-06)


### Features

* add first sonar scan ([d272eca](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/d272ecaf70d6cc813fec769f80d8110c3131eff5))
* add first sonar scan ([e5542ed](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/e5542ede5551102af6bec1c1e13097642daa46b9))
* ci improvements ([98d9ec8](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/98d9ec8dacc14662578832c7419ff49e224fa4f3))
* **deps:** migrate to ffreis-platform-standards ([#14](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/14)) ([15ef3bd](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/15ef3bd1da1425098a3b018279aa7e2939d5422f))
* improve ci ([2aff57a](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/2aff57aaf06b0e9d0855073c3759e52664999b44))
* improvements based on usage ([31af9db](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/31af9dbc9492200d9c552ae80b998652b04bdada))
* improvements based on usage ([32af969](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/32af969de0d9df15042b6f19b29a9ab0d4e1d49b))
* more workflows ([bbce2ca](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/bbce2ca67ac304523f2a2b10f5d14ee98ed72b25))
* more workflows ([20be8d5](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/20be8d55a6d3add600cd0aabef6cf3bcd2da51ff))
* rust workflows ([8506783](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/8506783ac01483648db2cd1ff2622be7fa77926a))
* setup repo ([39cf709](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/39cf709ea34339d490f567ec730ada4f842a4bb5))


### Bug Fixes

* actionlint + grype gating ([623b540](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/623b54040ffba0ed0e15d003ecb99a61ae59a6a0))
* address PR review comments on dependabot and concurrency groups ([2d66a7a](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/2d66a7a1026662d008f1cb7f112c1f09e0cac760))
* address PR review feedback ([33a9d12](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/33a9d126ccb22d5843046b728bec9ffeaeeed7e5))
* address review feedback on dependabot, concurrency groups ([c60e3a4](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/c60e3a4175d60bfa1d6de1718a91fc95036d96a0))
* address six code review issues from initial scaffolding PR ([43c5969](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/43c59696eda74362a0e4e98b268552a5ef72c26a))
* ci ([f762609](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/f762609c3cd6d1317867a7504445385910d6f16a))
* ci ([27f20b2](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/27f20b2217ce940ecfdd2bc9a4ff475e0f43ae0f))
* ci ([aee4b39](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/aee4b398833ae09ec8e32221cd8c8e5bda1bb8c7))
* ci ([8620739](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/8620739241c2d3e79b2cec564d9db59790bac1f9))
* ci ([d734e05](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/d734e050a2e838dffc19c31d13882c3744b6c298))
* ci ([#12](https://github.com/FelipeFuhr/ffreis-workflows-rust/issues/12)) ([98d5d13](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/98d5d139853a40c6ae4175ead25a5b09e4130104))
* dependabot dedup, concurrency group correctness ([5b5e8eb](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/5b5e8ebb8127c6afe570ac2ace9d3d18037a1853))
* fix ci ([91e5aea](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/91e5aea780aaafd1793415451448f748ebe08905))
* fix ci ([de4c187](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/de4c18749a0d64dc50de0245ea2c56eb4f63058d))
* merge with main ([4b7b053](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/4b7b05396140001b5dbad45b80d5848bc033b297))
* remove duplicate dependabot/Renovate overlap and fix concurrency groups ([a38b297](https://github.com/FelipeFuhr/ffreis-workflows-rust/commit/a38b297790a4120e8b15bbd2ae0328da96373f34))
