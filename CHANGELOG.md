# Changelog

## [0.3.4](https://github.com/lwoggardner/ffi-libfuse/compare/v0.3.3...v0.3.4) (2023-01-08)


### Bug Fixes

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
