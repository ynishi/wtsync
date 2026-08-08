## Platform-neutral recursive directory watcher.
##
## `watch` blocks and calls `handler` for every file/directory created below
## `root`.
##
## - macOS: FSEvents, which is recursive by nature
## - Linux: inotify, which watches a single directory per watch descriptor;
##   watches are seeded from the existing tree and extended as new
##   directories appear

type
  CreatedHandler* = proc(path: string, isDir: bool)

when defined(macosx):
  import ./fsevents
  when defined(debug):
    import std/strutils

  # The FSEvents callback is a plain C function pointer with no closure
  # environment, so the handler is reached through a module-level var.
  # `watch` is blocking and single threaded, so one slot is enough.
  var gHandler: CreatedHandler

  proc onFSEvent(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: pointer,
    numEvents: csize_t,
    eventPaths: pointer,
    eventFlags: ptr FSEventStreamEventFlags,
    eventIds: ptr FSEventStreamEventId
  ) {.cdecl, gcsafe.} =
    let paths = cast[ptr UncheckedArray[cstring]](eventPaths)
    let flags = cast[ptr UncheckedArray[FSEventStreamEventFlags]](eventFlags)

    for i in 0..<numEvents:
      let eventFlag = flags[i]
      let eventPath = $paths[i]

      when defined(debug):
        let hexFlag = "0x" & cast[uint32](eventFlag).toHex(8)
        stderr.writeLine "[debug] ", eventPath, " flags=", hexFlag

      if (eventFlag and kFSEventStreamEventFlagItemCreated) == 0:
        continue

      let isDir = (eventFlag and kFSEventStreamEventFlagItemIsDir) != 0
      let isFile = (eventFlag and kFSEventStreamEventFlagItemIsFile) != 0
      if not (isDir or isFile):
        continue

      # SAFETY: single threaded, the run loop and gHandler share one thread
      {.cast(gcsafe).}:
        if gHandler != nil:
          gHandler(eventPath, isDir)

  proc watch*(root: string, handler: CreatedHandler, latency: float = 0.3) =
    gHandler = handler
    startWatch(root, onFSEvent, nil, latency)

elif defined(linux):
  import std/[os, posix, strutils, tables]
  import ./core
  import ./inotify

  const watchMask = IN_CREATE or IN_MOVED_TO or IN_DELETE_SELF or
                    IN_MOVE_SELF or IN_ONLYDIR

  proc watch*(root: string, handler: CreatedHandler, latency: float = 0.3) =
    ## `latency` exists for parity with the FSEvents backend; inotify delivers
    ## events without coalescing, so it is unused here.
    let fd = inotify_init1(cint(IN_CLOEXEC))
    if fd < 0:
      quit("Failed to init inotify: " & $strerror(errno), 1)

    var watched = initTable[cint, string]()

    proc addWatch(dir: string) =
      let wd = inotify_add_watch(fd, cstring(dir), watchMask)
      if wd < 0:
        stderr.writeLine "wtsync: cannot watch ", dir, ": ", $strerror(errno)
      else:
        watched[wd] = dir

    proc addTree(dir: string) =
      ## Watches a freshly created directory and replays what it already
      ## contains. `git worktree add` writes the .git file immediately after
      ## creating the directory, so those entries can land before the watch
      ## is installed. Handlers are idempotent, so a replayed duplicate is
      ## harmless.
      addWatch(dir)
      for kind, path in walkDir(dir):
        case kind
        of pcFile, pcLinkToFile:
          handler(path, false)
        of pcDir, pcLinkToDir:
          handler(path, true)
          if path.extractFilename.startsWith("."):
            continue
          # git repositories / worktrees only need their top level watched
          let gitPath = path / ".git"
          if fileExists(gitPath) or dirExists(gitPath):
            addWatch(path)
          else:
            addTree(path)

    addWatch(root)
    for dir in findAllDirs(root):
      addWatch(dir)

    var buf = newSeq[byte](64 * 1024)
    while true:
      let n = read(fd, addr buf[0], buf.len)
      if n < 0:
        if errno == EINTR:
          continue
        stderr.writeLine "wtsync: inotify read failed: ", $strerror(errno)
        break
      if n == 0:
        break

      var i = 0
      while i + InotifyEventSize <= n:
        let ev = cast[ptr InotifyEvent](addr buf[i])
        let wd = ev.wd
        let mask = ev.mask
        let nameLen = int(ev.len)
        var name = ""
        if nameLen > 0:
          # the name field is NUL padded to a multiple of the event size
          name = $cast[cstring](addr buf[i + InotifyEventSize])
        i += InotifyEventSize + nameLen

        if (mask and (IN_IGNORED or IN_DELETE_SELF or IN_MOVE_SELF)) != 0:
          watched.del(wd)
          continue
        if (mask and IN_Q_OVERFLOW) != 0:
          stderr.writeLine "wtsync: inotify queue overflow, events were dropped"
          continue
        if name.len == 0:
          continue

        let parent = watched.getOrDefault(wd, "")
        if parent.len == 0:
          continue

        let path = parent / name
        let isDir = (mask and IN_ISDIR) != 0
        handler(path, isDir)
        if isDir and not name.startsWith("."):
          addTree(path)

    discard close(fd)

else:
  proc watch*(root: string, handler: CreatedHandler, latency: float = 0.3) =
    quit("watch is only supported on macOS and Linux", 1)
