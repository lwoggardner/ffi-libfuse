# frozen_string_literal: true

module FFI
  class Stat
    # File type mask
    S_IFMT   = 0o170000

    # FIFO
    S_IFIFO  = 0o010000

    # Character device
    S_IFCHR  = 0o020000

    # Directory
    S_IFDIR  = 0o040000

    # Block device
    S_IFBLK  = 0o060000

    # Regular file
    S_IFREG  = 0o100000

    # Symbolic link
    S_IFLNK  = 0o120000

    # Socket
    S_IFSOCK = 0o140000
  end
end
