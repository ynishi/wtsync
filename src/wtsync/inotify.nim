## Linux inotify API - minimal Nim FFI bindings

const
  IN_CREATE* = 0x00000100'u32
  IN_MOVED_TO* = 0x00000080'u32
  IN_DELETE_SELF* = 0x00000400'u32
  IN_MOVE_SELF* = 0x00000800'u32
  IN_Q_OVERFLOW* = 0x00004000'u32
  IN_IGNORED* = 0x00008000'u32
  IN_ONLYDIR* = 0x01000000'u32
  IN_ISDIR* = 0x40000000'u32

  IN_CLOEXEC* = 0x00080000'u32
  IN_NONBLOCK* = 0x00000800'u32

proc inotify_init1*(flags: cint): cint
  {.importc: "inotify_init1", header: "<sys/inotify.h>".}

proc inotify_add_watch*(fd: cint, name: cstring, mask: uint32): cint
  {.importc: "inotify_add_watch", header: "<sys/inotify.h>".}

proc inotify_rm_watch*(fd: cint, wd: cint): cint
  {.importc: "inotify_rm_watch", header: "<sys/inotify.h>".}

type
  InotifyEvent* = object
    ## Mirrors `struct inotify_event`. The variable-length `name` field is
    ## read separately from the raw buffer, right after this header.
    wd*: cint
    mask*: uint32
    cookie*: uint32
    len*: uint32

const InotifyEventSize* = 16

static:
  doAssert sizeof(InotifyEvent) == InotifyEventSize
