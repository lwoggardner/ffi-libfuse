# Changelog

## [0.3.3](https://github.com/lwoggardner/ffi-libfuse/compare/v0.0.1...v0.3.3) (2023-01-07)


### ⚠ BREAKING CHANGES

* Support downstream RFuse/RFuseFS

### Features

* FFI::Libfuse::Filesystem - base filesystems ([5b19005](https://github.com/lwoggardner/ffi-libfuse/commit/5b19005c4b1ff2237b85c4854f481ea6e3625c62))


### Code Refactoring

* Support downstream RFuse/RFuseFS ([e6b3fb5](https://github.com/lwoggardner/ffi-libfuse/commit/e6b3fb552b8881dbf28f014617b7412f2542aaa3))


### Miscellaneous Chores

* **github:** release 0.3.3 ([b54a56f](https://github.com/lwoggardner/ffi-libfuse/commit/b54a56f3f93f15c7684aa2cb2c2dd38c9d033e7f))

## [0.3.2](https://github.com/lwoggardner/ffi-libfuse/compare/v0.3.0...v0.3.2) (2023-01-07)


### Miscellaneous Chores

* fix release-please action ([fd55030](https://github.com/lwoggardner/ffi-libfuse/commit/fd550301248ebd9616da457ef8c2d88a7e55f819))

## [0.3.0](https://github.com/lwoggardner/ffi-libfuse/compare/v0.2.1...v0.3.0) (2023-01-07)


### Miscellaneous Chores

* fix release-please action ([57d43e9](https://github.com/lwoggardner/ffi-libfuse/commit/57d43e9cac552b1b36469092a6278058893cadc4))

## [0.2.1](https://github.com/lwoggardner/ffi-libfuse/compare/v0.1.0...v0.2.1) (2023-01-07)

### Miscellaneous Chores

* release 0.2.1 ([bb0ef37](https://github.com/lwoggardner/ffi-libfuse/commit/bb0ef37c05a41c6b51a14e5cae292b2d7b75ef1c))

## [0.1.0](https://github.com/lwoggardner/ffi-libfuse/compare/v0.0.1...v0.1.0) (2023-01-07)

### ⚠ BREAKING CHANGES

* Support downstream RFuse/RFuseFS
* Changed option parsing.

  {FFI::Libfuse::Main#fuse_options} takes a FuseArgs parameter and fuse_opt_proc is not used

### Features

* FFI::Libfuse::Filesystem - base filesystems ([5b19005](https://github.com/lwoggardner/ffi-libfuse/commit/5b19005c4b1ff2237b85c4854f481ea6e3625c62))

### Code Refactoring

* Support downstream RFuse/RFuseFS ([e6b3fb5](https://github.com/lwoggardner/ffi-libfuse/commit/e6b3fb552b8881dbf28f014617b7412f2542aaa3))
* Test on OSX with macFuse
