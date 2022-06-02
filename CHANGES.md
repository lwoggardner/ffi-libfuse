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
