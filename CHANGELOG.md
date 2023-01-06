# Changelog

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
