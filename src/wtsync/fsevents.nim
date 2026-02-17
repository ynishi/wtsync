## macOS FSEvents API - minimal Nim FFI bindings

{.passL: "-framework CoreServices".}
{.passC: "-Wno-incompatible-function-pointer-types".}

type
  FSEventStreamObj {.importc: "struct __FSEventStream",
                     header: "<CoreServices/CoreServices.h>", final, pure.} = object
  FSEventStreamRef* = ptr FSEventStreamObj
  ConstFSEventStreamRef* = ptr FSEventStreamObj

  CFAllocatorRef = pointer
  CFArrayRef = pointer
  CFStringRef* = pointer
  CFRunLoopRef* = pointer
  CFTimeInterval* = cdouble
  FSEventStreamEventId* = uint64
  FSEventStreamEventFlags* = uint32
  FSEventStreamCreateFlags* = uint32

  FSEventStreamCallback* = proc(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: pointer,
    numEvents: csize_t,
    eventPaths: pointer,
    eventFlags: ptr FSEventStreamEventFlags,
    eventIds: ptr FSEventStreamEventId
  ) {.cdecl, gcsafe.}

  FSEventStreamContext* = object
    version: clong
    info: pointer
    retain: pointer
    release: pointer
    copyDescription: pointer

const
  kFSEventStreamEventIdSinceNow*: FSEventStreamEventId = 0xFFFFFFFFFFFFFFFF'u64
  kFSEventStreamCreateFlagFileEvents*: FSEventStreamCreateFlags = 0x00000010
  kFSEventStreamEventFlagItemCreated*: FSEventStreamEventFlags = 0x00000100
  kFSEventStreamEventFlagItemIsFile*: FSEventStreamEventFlags = 0x00010000
  kFSEventStreamEventFlagItemIsDir*: FSEventStreamEventFlags = 0x00020000

const kCFStringEncodingUTF8: uint32 = 0x08000100

proc CFStringCreateWithCString(
  allocator: CFAllocatorRef, cStr: cstring, encoding: uint32
): CFStringRef {.importc, header: "<CoreFoundation/CoreFoundation.h>".}

proc CFArrayCreate(
  allocator: CFAllocatorRef, values: ptr pointer, numValues: clong, callbacks: pointer
): CFArrayRef {.importc, header: "<CoreFoundation/CoreFoundation.h>".}

proc CFRunLoopGetCurrent(): CFRunLoopRef
  {.importc, header: "<CoreFoundation/CoreFoundation.h>".}

proc CFRunLoopRun*()
  {.importc, header: "<CoreFoundation/CoreFoundation.h>".}

var kCFRunLoopDefaultMode* {.importc, header: "<CoreFoundation/CoreFoundation.h>".}: CFStringRef

proc FSEventStreamCreate(
  allocator: CFAllocatorRef, callback: FSEventStreamCallback,
  context: ptr FSEventStreamContext, pathsToWatch: CFArrayRef,
  sinceWhen: FSEventStreamEventId, latency: CFTimeInterval,
  flags: FSEventStreamCreateFlags
): FSEventStreamRef {.importc, header: "<CoreServices/CoreServices.h>".}

proc FSEventStreamScheduleWithRunLoop(
  streamRef: FSEventStreamRef, runLoop: CFRunLoopRef, runLoopMode: CFStringRef
) {.importc, header: "<CoreServices/CoreServices.h>".}

proc FSEventStreamStart(
  streamRef: FSEventStreamRef
): bool {.importc, header: "<CoreServices/CoreServices.h>".}

proc FSEventStreamStop(
  streamRef: FSEventStreamRef
) {.importc, header: "<CoreServices/CoreServices.h>".}

proc FSEventStreamInvalidate(
  streamRef: FSEventStreamRef
) {.importc, header: "<CoreServices/CoreServices.h>".}

proc FSEventStreamRelease(
  streamRef: FSEventStreamRef
) {.importc, header: "<CoreServices/CoreServices.h>".}

proc startWatch*(path: string, callback: FSEventStreamCallback, info: pointer = nil, latency: float = 0.5) =
  ## Recursively watches path and calls callback on events. Blocking.
  ## info: pointer passed as clientCallBackInfo to the callback
  var cfStr = CFStringCreateWithCString(nil, cstring(path), kCFStringEncodingUTF8)
  var cfStrPtr = cast[pointer](cfStr)
  let pathsToWatch = CFArrayCreate(nil, addr cfStrPtr, 1, nil)

  var context = FSEventStreamContext(
    version: 0, info: info, retain: nil, release: nil, copyDescription: nil
  )

  let stream = FSEventStreamCreate(
    nil, callback, addr context, pathsToWatch,
    kFSEventStreamEventIdSinceNow, CFTimeInterval(latency),
    kFSEventStreamCreateFlagFileEvents
  )

  if stream.isNil:
    quit("Failed to create FSEventStream", 1)

  FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)

  if not FSEventStreamStart(stream):
    quit("Failed to start FSEventStream", 1)

  echo "watching: ", path
  try:
    CFRunLoopRun()
  finally:
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
