# Changelog

## [0.4.4](https://github.com/lwoggardner/ffi-libfuse/compare/v0.4.3...v0.4.4) (2024-12-29)


### Bug Fixes

* fuse buffer adding NUL character when creating from a String ([#35](https://github.com/lwoggardner/ffi-libfuse/issues/35)) ([e07ebfe](https://github.com/lwoggardner/ffi-libfuse/commit/e07ebfeff4001a7d48ad457604e9f5f9191f96de)), closes [#34](https://github.com/lwoggardner/ffi-libfuse/issues/34)

## [0.4.3](https://github.com/lwoggardner/ffi-libfuse/compare/v0.4.2...v0.4.3) (2024-12-25)


### Miscellaneous Chores

* release 0.4.3 ([341e2ce](https://github.com/lwoggardner/ffi-libfuse/commit/341e2ce3a2cf362bf2bdc2433ea0d1e1c843775c))

## [0.4.2](https://github.com/lwoggardner/ffi-libfuse/compare/v0.4.1...v0.4.2) (2024-12-16)


### Bug Fixes

* bugs in Adapter::Safe and virtual filesystem operations ([decf7ae](https://github.com/lwoggardner/ffi-libfuse/commit/decf7ae024eee4bb565f67abfe493a14e5fa9cca))

## [0.4.1](https://github.com/lwoggardner/ffi-libfuse/compare/v0.4.0...v0.4.1) (2024-10-26)


### Bug Fixes

* support alpine linux with musl libc and fuse 3.16 ([65d362d](https://github.com/lwoggardner/ffi-libfuse/commit/65d362d7f3e87bca426742cccaabc9f421e6fc38)), closes [#26](https://github.com/lwoggardner/ffi-libfuse/issues/26) [#27](https://github.com/lwoggardner/ffi-libfuse/issues/27)

## [0.4.0](https://github.com/lwoggardner/ffi-libfuse/compare/v0.3.4...v0.4.0) (2024-01-21)


### ⚠ BREAKING CHANGES

* **filesystem:** Fuse callbacks :init and :destroy are no longer passed on to sub-filesystems.
* **adapters:** Adapter::Debug now includes Adapter::Safe.
* Option parsing errors via raise exception rather than return false/nil

### Features

* **adapters:** Adapter::Debug now includes Adapter::Safe. ([a595304](https://github.com/lwoggardner/ffi-libfuse/commit/a59530427d7eb85961a724969eaa6ec099c5e4f6))
* **filesystem:** Support :rename operation in virtual filesystems ([a595304](https://github.com/lwoggardner/ffi-libfuse/commit/a59530427d7eb85961a724969eaa6ec099c5e4f6))
* **filesystem:** Support symlinks and hardlinks in virtual filesystems (VirtualDir/MemoryFS) ([a595304](https://github.com/lwoggardner/ffi-libfuse/commit/a59530427d7eb85961a724969eaa6ec099c5e4f6))
* Option parsing errors via raise exception rather than return false/nil ([a595304](https://github.com/lwoggardner/ffi-libfuse/commit/a59530427d7eb85961a724969eaa6ec099c5e4f6))


### Bug Fixes

* **fuse2compat:** Enhanced Fuse2 compatibility in Fuse2Compat module ([a595304](https://github.com/lwoggardner/ffi-libfuse/commit/a59530427d7eb85961a724969eaa6ec099c5e4f6))
* symlinks and hard links ([a595304](https://github.com/lwoggardner/ffi-libfuse/commit/a59530427d7eb85961a724969eaa6ec099c5e4f6))

## [0.3.4](https://github.com/lwoggardner/ffi-libfuse/compare/v0.3.3...v0.3.4) (2023-01-08)


### Miscellaneous Chores

* **github:** allow downstream gems to use gem_version etc ([73f3b92](https://github.com/lwoggardner/ffi-libfuse/commit/73f3b92f5e8a1f86a9f6053b71470d7c113e6d19))

## [0.3.3](https://github.com/lwoggardner/ffi-libfuse/compare/v0.1.0...v0.3.3) (2023-01-07)

### Miscellaneous Chores

* **github:** release 0.3.3 ([b54a56f](https://github.com/lwoggardner/ffi-libfuse/commit/b54a56f3f93f15c7684aa2cb2c2dd38c9d033e7f))
  
  Using github actions

## 0.1.0 (2023-01-07)

### ⚠ BREAKING CHANGES

* Support downstream RFuse/RFuseFS
* Changed option parsing.

  {FFI::Libfuse::Main#fuse_options} takes a FuseArgs parameter and fuse_opt_proc is not used

### Features

* FFI::Libfuse::Filesystem - base filesystems ([5b19005](https://github.com/lwoggardner/ffi-libfuse/commit/5b19005c4b1ff2237b85c4854f481ea6e3625c62))

### Code Refactoring

* Support downstream RFuse/RFuseFS ([e6b3fb5](https://github.com/lwoggardner/ffi-libfuse/commit/e6b3fb552b8881dbf28f014617b7412f2542aaa3))
* Test on OSX with macFuse
