# Changelog

## [0.1.0](https://github.com/lwoggardner/ffi-libfuse/compare/v0.0.1...v0.1.0) (2023-01-07)


### ⚠ BREAKING CHANGES

* Support downstream RFuse/RFuseFS

### Features

* FFI::Libfuse::Filesystem - base filesystems ([5b19005](https://github.com/lwoggardner/ffi-libfuse/commit/5b19005c4b1ff2237b85c4854f481ea6e3625c62))


### Code Refactoring

* Support downstream RFuse/RFuseFS ([e6b3fb5](https://github.com/lwoggardner/ffi-libfuse/commit/e6b3fb552b8881dbf28f014617b7412f2542aaa3))

## [0.2.0](https://github.com/lwoggardner/ffi-libfuse/compare/v0.0.1...v0.2.0) (2023-01-04)


### ⚠ BREAKING CHANGES

* Move to Github Actions

### Code Refactoring

* Move to Github Actions ([6d27335](https://github.com/lwoggardner/ffi-libfuse/commit/6d273359a020a004cae4c03ca83470c8ce7b5999))


### Miscellaneous Chores

* release 0.2.0 ([8dcdeda](https://github.com/lwoggardner/ffi-libfuse/commit/8dcdedaf3e144baddafd0239b99544005cb79ec5))

0.1.0  / 2022-04
------------------

#### BREAKING changes
* Changed option parsing.

  {FFI::Libfuse::Main#fuse_options} now takes a FuseArgs parameter and fuse_opt_proc is not used

#### New Features
* Implemented helper filesystems in {FFI::Libfuse::Filesystem}

#### Fixes
* Test on OSX with macFuse
* Lots
