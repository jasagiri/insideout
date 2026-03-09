import std/atomics
import std/macros
import std/posix
import std/strformat

import pkg/cps
import pkg/trees/wavl

import insideout/times
import insideout/importer
import insideout/atomic/refs
export refs

when defined(linux):
  macro timerfdh(n: untyped): untyped = importer(n, newLit"<sys/timerfd.h>")
  macro timerfdh(s: untyped; n: untyped): untyped =
    importer(n, newLit"<sys/timerfd.h>", s)
  macro signalfdh(n: untyped): untyped = importer(n, newLit"<sys/signalfd.h>")
  macro signalfdh(s: untyped; n: untyped): untyped =
    importer(n, newLit"<sys/signalfd.h>", s)
  macro eventfdh(n: untyped): untyped = importer(n, newLit"<sys/eventfd.h>")
  macro epollh(n: untyped): untyped = importer(n, newLit"<sys/epoll.h>")
  macro epollh(s: untyped; n: untyped): untyped =
    importer(n, newLit"<sys/epoll.h>", s)

  let EPOLL_CTL_ADD {.epollh.}: cint
  let EPOLL_CTL_MOD {.epollh.}: cint
  let EPOLL_CTL_DEL {.epollh.}: cint

elif defined(macosx) or defined(darwin) or defined(bsd):
  macro kqueueh(n: untyped): untyped = importer(n, newLit"<sys/event.h>")
  macro kqueueh(s: untyped; n: untyped): untyped =
    importer(n, newLit"<sys/event.h>", s)

macro stringh(n: untyped): untyped = importer(n, newLit"<string.h>")

type
  PollError* = object of OSError

  Id* = distinct culonglong
  Fd* = distinct cint

  Event* = enum
    Read
    Write
    Error
    HangUp
    NoPeer
    OneShot
    Level
    Edge
    Priority
    Exclusive
    WakeUp
    Message

  RecordObj = object
    c: Continuation
    id: Id
    fd: Fd
    mask: cuint
    events: set[Event]
  Record = ref RecordObj

  Registry = WAVLTree[Id, Record]
  Watchers = WAVLTree[Fd, Registry]

  EventQueueObj = object
    interest: Fd
    registry: Registry
    watchers: Watchers
    nextId: Atomic[uint64]

  EventQueue* = AtomicRef[EventQueueObj]

when defined(linux):
  type
    epoll_events = enum
      EPOLLIN             = 0x001      ## There is data to read.
      EPOLLPRI            = 0x002      ## There is urgent data to read.
      EPOLLOUT            = 0x004      ## Writing now will not block.
      EPOLLERR            = 0x008      ## Error condition.
      EPOLLHUP            = 0x010      ## Hung up.
      EPOLLRDNORM         = 0x040      ## Normal data may be read.
      EPOLLRDBAND         = 0x080      ## Priority data may be read.
      EPOLLWRNORM         = 0x100      ## Writing now will not block.
      EPOLLWRBAND         = 0x200      ## Priority data may be written.
      EPOLLMSG            = 0x400      ## Input message is available.
      EPOLLRDHUP          = 0x2000     ## Socket peer closed connection.
      EPOLLEXCLUSIVE      = 1 shl 28   ## Sets exclusive wakeup mode.
      EPOLLWAKEUP         = 1 shl 29   ## Wakes up the blocked system call.
      EPOLLONESHOT        = 1 shl 30   ## Sets one-shot behavior.
      EPOLLET             = 1 shl 31   ## Enables edge-triggered events.

    epoll_event* {.epollh: "struct epoll_event".} = object
      events: cuint
      data: epoll_data

    epoll_data {.epollh: "union epoll_data".} = object
      u64: uint64

  type EventInfo* = epoll_event

elif defined(macosx) or defined(darwin) or defined(bsd):
  type
    kevent* {.kqueueh: "struct kevent".} = object
      ident*: uint
      filter*: cshort
      flags*: cushort
      fflags*: cuint
      data*: int
      udata*: pointer

  const
    EVFILT_READ* = -1.cshort
    EVFILT_WRITE* = -2.cshort
    EVFILT_AIO* = -3.cshort
    EVFILT_VNODE* = -4.cshort
    EVFILT_PROC* = -5.cshort
    EVFILT_SIGNAL* = -6.cshort
    EVFILT_TIMER* = -7.cshort
    EVFILT_MACHPORT* = -8.cshort
    EVFILT_FS* = -9.cshort
    EVFILT_USER* = -10.cshort
    EVFILT_VM* = -12.cshort

    EV_ADD* = 0x0001.cushort
    EV_DELETE* = 0x0002.cushort
    EV_ENABLE* = 0x0004.cushort
    EV_DISABLE* = 0x0008.cushort
    EV_ONESHOT* = 0x0010.cushort
    EV_CLEAR* = 0x0020.cushort
    EV_RECEIPT* = 0x0040.cushort
    EV_DISPATCH* = 0x0080.cushort
    EV_UDATA_SPECIFIC* = 0x0100.cushort
    EV_FLAG0* = 0x1000.cushort
    EV_FLAG1* = 0x2000.cushort
    EV_ERROR* = 0x4000.cushort
    EV_EOF* = 0x8000.cushort

  type EventInfo* = kevent

const
  invalidId*: Id = 0.Id
  invalidFd*: Fd = -1.Fd
  AllEvents* = {Read, Write, Error, HangUp, NoPeer, Edge, Priority,
                Exclusive, WakeUp, Message}

proc checkErr[T](err: T): T {.discardable.} =
  if err.cint == -1:
    raise OSError.newException $strerror(errno)
  else:
    result = err

when defined(linux):
  type
    itimerspec {.timerfdh: "struct itimerspec".} = object
      it_interval: TimeSpec
      it_value: TimeSpec

  proc timerfd_create(clock: ClockId; flags: cint): Fd {.timerfdh.}
  proc timerfd_settime(fd: Fd; flags: cint; new_value: ptr itimerspec;
                       old_value: ptr itimerspec): cint {.timerfdh.}
  proc timerfd_gettime(fd: Fd; curr_value: ptr itimerspec): cint {.timerfdh.}
  let TFD_NONBLOCK* {.timerfdh.}: cint
  let TFD_CLOEXEC* {.timerfdh.}: cint
  let TFD_TIMER_ABSTIME* {.timerfdh.}: cint
  let TFD_TIMER_CANCEL_ON_SET* {.timerfdh.}: cint

  type
    signalfd_siginfo* {.signalfdh: "struct signalfd_siginfo".} = object
      ssi_signo*: uint32        ## Signal number
      ssi_errno*: int32         ## Error number (unused)
      ssi_code*: int32          ## Signal code
      ssi_pid*: uint32          ## PID of sender
      ssi_uid*: uint32          ## Real UID of sender
      ssi_fd*: int32            ## File descriptor (SIGIO)
      ssi_tid*: uint32          ## Kernel timer ID (POSIX timers)
      ssi_band*: uint32         ## Band event (SIGIO)
      ssi_overrun*: uint32      ## POSIX timer overrun count
      ssi_trapno*: uint32       ## Trap number that caused signal
      ssi_status*: int32        ## Exit status or signal (SIGCHLD)
      ssi_int*: int32           ## Integer sent by sigqueue(3)
      ssi_ptr*: uint64          ## Pointer sent by sigqueue(3)
      ssi_utime*: uint64        ## User CPU time consumed (SIGCHLD)
      ssi_stime*: uint64        ## System CPU time consumed (SIGCHLD)
      ssi_addr*: uint64         ## Address that generated signal (for hardware-generated signals)
      ssi_addr_lsb*: uint16     ## Least significant bit of address (SIGBUS)
      pad2: uint16
      ssi_syscall*: uint32      ## System call number (SIGSYS)
      ssi_call_addr*: uint64    ## Address of system call instruction (SIGSYS)
      ssi_arch*: uint32         ## AUDIT_ARCH_* of syscall (SIGSYS)
      pad: array[0..27, uint8]  ## Pad size to 128 bytes

  proc readSigInfo*(fd: Fd): signalfd_siginfo =
    ## read a signalfd_siginfo from `fd`
    while EINTR == read(fd.cint, addr result, sizeof(signalfd_siginfo)):
      discard

  let SFD_NONBLOCK* {.signalfdh.}: cint
  let SFD_CLOEXEC* {.signalfdh.}: cint
  proc signalfd*(fd: Fd; mask: ptr Sigset; flags: cint): Fd {.signalfdh.}

  converter toCint(event: epoll_events): uint32 = event.ord.uint32

  proc eventfd(count: culonglong; flags: cint): Fd {.noconv, eventfdh.}

  proc epoll_create(flags: cint): Fd {.noconv, epollh: "epoll_create1".}

  proc epoll_ctl(epfd: Fd; op: cint; fd: Fd; event: ptr epoll_event): cint
    {.noconv, epollh.}

  proc epoll_wait(epfd: cint; events: ptr epoll_event;
                  maxevents: cint; timeout: cint): cint {.noconv, epollh.}

  proc epoll_pwait2(epfd: cint; events: ptr epoll_event; maxevents: cint;
                    timeout: ptr TimeSpec; sigmask: ptr Sigset): cint
                   {.noconv, epollh.}

elif defined(macosx) or defined(darwin) or defined(bsd):
  type
    signalfd_siginfo* = object
      ssi_signo*: uint32

  proc kqueue(): Fd {.kqueueh.}
  proc kevent_proc(kq: Fd; changelist: ptr kevent; nchanges: cint;
              eventlist: ptr kevent; nevents: cint;
              timeout: ptr TimeSpec): cint {.kqueueh: "kevent".}

  proc readSigInfo*(fd: Fd): signalfd_siginfo =
    var signo: cint
    while EINTR == read(fd.cint, addr signo, sizeof(signo)):
      discard
    result.ssi_signo = signo.uint32

proc strsignal*(signo: cint): cstring {.stringh.}

proc name*(info: signalfd_siginfo): string =
  $strsignal(info.ssi_signo.cint)

proc repr*(info: signalfd_siginfo): string =
  ## return a string representation of the signalfd_siginfo
  ## by building up a string of all the interesting fields.
  result = fmt"{info.name}("
  when defined(linux):
    if info.ssi_errno != 0:
      result.add fmt"ssi_errno: {info.ssi_errno}, "
    if info.ssi_code != 0:
      result.add fmt"ssi_code: {info.ssi_code}, "
    if info.ssi_pid != 0:
      result.add fmt"ssi_pid: {info.ssi_pid}, "
    if info.ssi_uid != 0:
      result.add fmt"ssi_uid: {info.ssi_uid}, "
    if info.ssi_fd != 0:
      result.add fmt"ssi_fd: {info.ssi_fd}, "
    if info.ssi_tid != 0:
      result.add fmt"ssi_tid: {info.ssi_tid}, "
    if info.ssi_band != 0:
      result.add fmt"ssi_band: {info.ssi_band}, "
    if info.ssi_overrun != 0:
      result.add fmt"ssi_overrun: {info.ssi_overrun}, "
    if info.ssi_trapno != 0:
      result.add fmt"ssi_trapno: {info.ssi_trapno}, "
    if info.ssi_status != 0:
      result.add fmt"ssi_status: {info.ssi_status}, "
    if info.ssi_int != 0:
      result.add fmt"ssi_int: {info.ssi_int}, "
    if info.ssi_ptr != 0:
      result.add fmt"ssi_ptr: {info.ssi_ptr}, "
    if info.ssi_utime != 0:
      result.add fmt"ssi_utime: {info.ssi_utime}, "
    if info.ssi_stime != 0:
      result.add fmt"ssi_stime: {info.ssi_stime}, "
    if info.ssi_addr != 0:
      result.add fmt"ssi_addr: {info.ssi_addr}, "
    if info.ssi_addr_lsb != 0:
      result.add fmt"ssi_addr_lsb: {info.ssi_addr_lsb}, "
    if info.ssi_syscall != 0:
      result.add fmt"ssi_syscall: {info.ssi_syscall}, "
    if info.ssi_call_addr != 0:
      result.add fmt"ssi_call_addr: {info.ssi_call_addr}, "
    if info.ssi_arch != 0:
      result.add fmt"ssi_arch: {info.ssi_arch}, "
  result.add ")"

proc `<`(a, b: Id): bool {.borrow, used.}
proc `==`(a, b: Id): bool {.borrow, used.}
proc `<`(a, b: Fd): bool {.borrow, used.}
proc `==`(a, b: Fd): bool {.borrow, used.}

proc close*(fd: var Fd) =
  if fd != invalidFd:
    while EINTR == posix.close(fd.cint):
      discard
    fd = invalidFd

proc destroy[K, V](tree: var WAVLTree[K, V]) {.raises: [].} =
  while tree.len > 0:
    try:
      tree.popMax
    except ValueError: # tree is empty
      break

proc deinit(eq: var EventQueueObj) {.raises: [].} =
  # close interest fd
  close eq.interest
  # clear out the watchers quickly
  reset eq.watchers
  # destroy queued continuations in reverse order
  destroy eq.registry
  for key, value in eq.fieldPairs:
    when value isnot Fd:
      reset value

proc `=destroy`(eq: var EventQueueObj) {.raises: [].} =
  deinit eq

proc deinit*(eq: var EventQueue) =
  ## deinitialize the eventqueue
  if not eq.isNil:
    deinit eq[]

template withNewEventQueue*(name: untyped; body: untyped): untyped =
  ## create and initialize an eventqueue named `name` and run
  ## `body` with it, deinitializing it at close of scope.
  var name {.inject.}: EventQueue
  init name
  try:
    body
  finally:
    deinit name

proc `=copy`*[T](dest: var EventQueueObj; src: EventQueueObj) {.error.}

proc delRegistry(eq: var EventQueueObj; fd: Fd) =
  if fd in eq.watchers:
    when defined(linux):
      checkErr epoll_ctl(eq.interest, EPOLL_CTL_DEL, fd, nil)
    elif defined(macosx) or defined(darwin) or defined(bsd):
      var ev: kevent
      ev.ident = fd.uint
      ev.filter = EVFILT_READ
      ev.flags = EV_DELETE
      discard kevent_proc(eq.interest, addr ev, 1, nil, 0, nil)
      ev.filter = EVFILT_WRITE
      discard kevent_proc(eq.interest, addr ev, 1, nil, 0, nil)
    var registry = eq.watchers.pop(fd)
    destroy registry

proc delRegistry(eq: var EventQueueObj; record: Record) =
  if not eq.registry.remove(record.id):
    raise Defect.newException "event not found"
  if record.fd != invalidFd:
    if record.fd in eq.watchers:
      if not eq.watchers[record.fd].remove(record.id):
        raise Defect.newException "event not found"
      if eq.watchers[record.fd].len == 0:
        eq.delRegistry record.fd
      else:
        raise Defect.newException "interest mod not impl"
  else:
    # Likely a timer on macOS
    when defined(macosx) or defined(darwin) or defined(bsd):
      var ev: kevent
      ev.ident = record.id.uint
      ev.filter = EVFILT_TIMER
      ev.flags = EV_DELETE
      discard kevent_proc(eq.interest, addr ev, 1, nil, 0, nil)

proc addRegistry(eq: var EventQueueObj; record: Record) =
  assert eq.interest != invalidFd
  eq.registry.insert(record.id, record)
  if record.fd in eq.watchers:
    eq.watchers[record.fd].insert(record.id, record)
  else:
    var registry: Registry
    registry.insert(record.id, record)
    eq.watchers[record.fd] = registry

template id(event: EventInfo): Id =
  when defined(linux):
    Id(event.data.u64)
  elif defined(macosx) or defined(darwin) or defined(bsd):
    Id(cast[uint](event.udata))

proc register(eq: var EventQueueObj; c: sink Continuation;
              fd: Fd; events: set[Event]): Id =
  assert eq.interest != invalidFd
  var id = fetchAdd(eq.nextId, 1, order = moAcquireRelease)
  var mask: cuint

  when defined(linux):
    var ev: epoll_event
    if true or HangUp in events:    # defaults to `on`
      ev.events = ev.events or EPOLLHUP
    if true or Error in events:     # defaults to `on`
      ev.events = ev.events or EPOLLERR
    if true or Priority in events:  # defaults to `on`
      ev.events = ev.events or EPOLLPRI
    if Read in events:
      ev.events = ev.events or EPOLLIN or EPOLLRDHUP
    if Write in events:
      ev.events = ev.events or EPOLLOUT
    if OneShot in events:
      ev.events = ev.events or EPOLLONESHOT
    if NoPeer in events:
      ev.events = ev.events or EPOLLRDHUP
    if WakeUp in events:
      ev.events = ev.events or EPOLLWAKEUP
    if Exclusive in events:
      ev.events = ev.events or EPOLLEXCLUSIVE
    if Message in events:
      ev.events = ev.events or EPOLLMSG
    if WakeUp in events:
      ev.events = ev.events or EPOLLWAKEUP
    if Level in events:
      raise Defect.newException "not implemented"
    elif Edge in events:
      ev.events = ev.events or EPOLLET
    else:
      raise Defect.newException "specify Edge or Level"
    ev.data.u64 = id
    mask = ev.events

  elif defined(macosx) or defined(darwin) or defined(bsd):
    # We'll register multiple events if needed
    discard

  var record =
    Record(c: c, id: Id(id), fd: fd, mask: mask, events: events)

  try:
    eq.addRegistry record
    when defined(linux):
      checkErr epoll_ctl(eq.interest, EPOLL_CTL_ADD, fd, addr ev)
    elif defined(macosx) or defined(darwin) or defined(bsd):
      var kevents: array[2, kevent]
      var n = 0
      var flags = EV_ADD or EV_ENABLE
      if OneShot in events: flags = flags or EV_ONESHOT
      if Edge in events: flags = flags or EV_CLEAR

      if Read in events:
        kevents[n].ident = fd.uint
        kevents[n].filter = EVFILT_READ
        kevents[n].flags = flags
        kevents[n].udata = cast[pointer](id)
        inc n
      if Write in events:
        kevents[n].ident = fd.uint
        kevents[n].filter = EVFILT_WRITE
        kevents[n].flags = flags
        kevents[n].udata = cast[pointer](id)
        inc n
      
      if n > 0:
        checkErr kevent_proc(eq.interest, addr kevents[0], n.cint, nil, 0, nil)
      
    result = Id(id)
  except CatchableError as e:
    eq.delRegistry record
    raise

proc register*(eq: EventQueue; c: sink Continuation;
               fd: Fd; events: set[Event]): Id =
  assert not eq.isNil
  register(eq[], c, fd, events)

proc unregister(eq: var EventQueueObj; id: Id) =
  assert eq.interest != invalidFd
  if id in eq.registry:
    eq.delRegistry eq.registry[id]

proc surrender(c: sink Continuation; eq: EventQueue;
               id: Id): Continuation {.cpsMagic.} =
  unregister(eq[], id)
  result = c

proc init(eq: var EventQueueObj) =
  ## initialize the eventqueue
  when defined(linux):
    eq.interest = checkErr epoll_create(O_CLOEXEC)
  elif defined(macosx) or defined(darwin) or defined(bsd):
    eq.interest = checkErr kqueue()
  assert eq.interest != invalidFd
  # ensure the first id != invalidId
  discard fetchAdd(eq.nextId, 1, order = moAcquireRelease)

proc init*(eq: var EventQueue) =
  if eq.isNil:
    new eq
    init eq[]
  assert eq[].interest != invalidFd

proc initEventQueue*(): EventQueue =
  ## return an initialized eventqueue
  init result

proc toSet(event: EventInfo): set[Event] =
  ## some liberties taken here for the composition reasons
  when defined(linux):
    if 0 != (event.events and EPOLLIN.ord.uint32):
      result.incl Read
    if 0 != (event.events and (EPOLLRDNORM.ord.uint32 or EPOLLRDBAND.ord.uint32)):
      result.incl Read
    if 0 != (event.events and EPOLLOUT.ord.uint32):
      result.incl Write
    if 0 != (event.events and (EPOLLWRNORM.ord.uint32 or EPOLLWRBAND.ord.uint32)):
      result.incl Write
    if 0 != (event.events and (EPOLLRDBAND.ord.uint32 or EPOLLWRBAND.ord.uint32)):
      result.incl Priority
    if 0 != (event.events and EPOLLPRI.ord.uint32):
      result.incl Priority
    if 0 != (event.events and EPOLLRDHUP.ord.uint32):
      result.incl NoPeer
    if 0 != (event.events and EPOLLERR.ord.uint32):
      result.incl Error
    if 0 != (event.events and EPOLLHUP.ord.uint32):
      result.incl HangUp
    if 0 != (event.events and EPOLLMSG.ord.uint32):
      result.incl Message
    if 0 != (event.events and EPOLLEXCLUSIVE.ord.uint32):
      result.incl Exclusive
    if 0 != (event.events and EPOLLWAKEUP.ord.uint32):
      result.incl WakeUp
    if 0 != (event.events and EPOLLET.ord.uint32):
      result.incl Edge
  elif defined(macosx) or defined(darwin) or defined(bsd):
    if event.filter == EVFILT_READ:
      result.incl Read
    if event.filter == EVFILT_WRITE:
      result.incl Write
    if event.filter == EVFILT_TIMER:
      result.incl Read
    if (event.flags and EV_ERROR) != 0:
      result.incl Error
    if (event.flags and EV_EOF) != 0:
      result.incl HangUp
    if (event.flags and EV_CLEAR) != 0:
      result.incl Edge

proc runEvent(eq: var EventQueueObj; event: var EventInfo) {.deprecated.} =
  if event.id in eq.registry:
    let record = eq.registry[event.id]
    var x = trampoline(move record.c)
    record.c = move x

template maybeInit(eq: var EventQueue): untyped =
  if eq.isNil:
    init eq
  assert eq[].interest != invalidFd

proc pruneOneShots(eq: var EventQueueObj; events: var openArray[EventInfo];
                   quantity: cint) =
  ## remove any one-shot events from the registry
  var i = quantity
  while i > 0:
    dec i
    let id = events[i].id
    let record = eq.registry[id]
    if OneShot in record.events:
      eq.delRegistry record

proc pruneOneShots*(eq: EventQueue; events: var openArray[EventInfo];
                    quantity: cint) =
  ## remove any one-shot events from the registry
  eq[].pruneOneShots(events, quantity)

proc wait*(eq: var EventQueue; events: var openArray[EventInfo];
           timeout: ptr TimeSpec; mask: ptr Sigset): cint =
  ## wait up to `timeout` for `events` under signal mask `mask`
  maybeInit eq
  when defined(linux):
    result = epoll_pwait2(eq[].interest.cint, cast[ptr epoll_event](addr events[0]),
                          events.len.cint, timeout, mask)
  elif defined(macosx) or defined(darwin) or defined(bsd):
    # kqueue doesn't have pwait2 equivalent that takes a signal mask directly
    # in the same way, but we can set the signal mask for the thread.
    # However, insideout seems to already do that in runtimes.nim.
    result = kevent_proc(eq[].interest, cast[ptr kevent](addr events[0]), 0,
                    cast[ptr kevent](addr events[0]), events.len.cint, timeout)

proc wait*(eq: var EventQueue; events: var openArray[EventInfo];
           timeout: float): cint =
  ## wait up to `timeout` seconds for `events`
  var ts = timeout.toTimeSpec
  result = wait(eq, events, timeout = addr ts, nil)

proc wait*(eq: var EventQueue; events: var openArray[EventInfo]): cint =
  ## wait for events
  result = wait(eq, events, nil, nil)

proc wait*(eq: var EventQueue): cint =
  ## wait for the next event and discard it
  var events: array[1, EventInfo]
  result = wait(eq, events)

proc run*(eq: EventQueue; events: var openArray[EventInfo]; quantity: cint) =
  if quantity > 0:
    var i = min(events.len, quantity)
    while i > 0:
      dec i
      eq[].runEvent(events[i])  # XXX: temporary

proc suspend(c: sink Continuation; eq: EventQueue;
             fd: Fd; events: set[Event]): Continuation {.cpsMagic.} =
  discard register(eq, c, fd, events)

proc register*(eq: EventQueue; fd: Fd; events: set[Event] = AllEvents): Id {.cps: Continuation.} =
  assert eq[].interest != invalidFd
  assert fd != invalidFd
  eq.suspend(fd, {Edge} + events)

proc cancel*(eq: EventQueue; id: Id): bool {.discardable.} =
  ## cancel the event with id `id`; false if the event was not found
  assert not eq.isNil
  result = id in eq[].registry
  if result:
    eq[].delRegistry eq[].registry[id]  # let it crash with KeyError

  when defined(macosx) or defined(darwin) or defined(bsd):
  proc suspendTimer(c: sink Continuation; eq: EventQueue;
                    timeout: float): Continuation {.cpsMagic.} =
    let id = fetchAdd(eq[].nextId, 1, order = moAcquireRelease)
    var ev: kevent
    ev.ident = id.uint
    ev.filter = EVFILT_TIMER
    ev.flags = EV_ADD or EV_ENABLE or EV_ONESHOT
    ev.data = int(timeout * 1000) # milliseconds
    ev.udata = cast[pointer](id)
    
    var record = Record(c: c, id: Id(id), fd: invalidFd, events: {Read, OneShot})
    eq[].addRegistry record
    
    checkErr kevent_proc(eq[].interest, addr ev, 1, nil, 0, nil)
    result = nil
  
  
proc sleep*(eq: EventQueue; timeout: float) {.cps: Continuation.} =
  ## sleep for `timeout` seconds
  when defined(linux):
    var fd = timerfd_create(CLOCK_BOOTTIME, TFD_NONBLOCK or TFD_CLOEXEC).Fd
    var it: itimerspec
    it.it_value = timeout.toTimeSpec
    checkErr timerfd_settime(fd, 0, addr it, nil)
    discard eq.register(fd, {Read, OneShot})
  elif defined(macosx) or defined(darwin) or defined(bsd):
    if timeout > 0:
      eq.suspendTimer(timeout)

when defined(linux):
  proc initSignalFd*(mask: Sigset): Fd {.raises: [OSError].} =
    result = signalfd(invalidFd, addr mask, SFD_NONBLOCK or SFD_CLOEXEC)
    if result == invalidFd:
      raise OSError.newException $strerror(errno)
elif defined(macosx) or defined(darwin) or defined(bsd):
  type SignalContext = object
    mask: Sigset
    writeEnd: Fd

  proc macOSSignalThread(arg: pointer): pointer {.noconv.} =
    var ctx = cast[ptr SignalContext](arg)
    let kq = kqueue()
    var kevents: seq[kevent] = @[]
    for sig in 1..31:
      var m = ctx.mask
      if 1 == sigismember(m, sig.cint):
        # debugEcho "Registering signal ", sig
        kevents.add kevent(ident: sig.uint, filter: EVFILT_SIGNAL, flags: EV_ADD)
    
    if kevents.len > 0:
      discard kevent_proc(kq, addr kevents[0], kevents.len.cint, nil, 0, nil)
    
    while true:
      var ev: kevent
      if 1 == kevent_proc(kq, nil, 0, addr ev, 1, nil):
        let sig = ev.ident.cint
        # debugEcho "Caught signal ", sig
        discard write(ctx.writeEnd.cint, addr sig, sizeof(sig))
      else:
        break
    
    discard posix.close(kq.cint)
    deallocShared(ctx)
    return nil

  proc initSignalFd*(mask: Sigset): Fd {.raises: [OSError].} =
    var fds: array[2, cint]
    if 0 != pipe(fds):
      raise OSError.newException $strerror(errno)
    # Set non-blocking on the read end
    let flags = fcntl(fds[0], F_GETFL, 0)
    discard fcntl(fds[0], F_SETFL, flags or O_NONBLOCK)
    
    let readEnd = fds[0].Fd
    let writeEnd = fds[1].Fd
    
    var ctx = cast[ptr SignalContext](allocShared(sizeof(SignalContext)))
    ctx.mask = mask
    ctx.writeEnd = writeEnd
    
    var thread: Pthread
    if 0 != pthread_create(addr thread, nil, macOSSignalThread, ctx):
      deallocShared(ctx)
      raise OSError.newException "unable to create signal thread"
    discard pthread_detach(thread)
        
    result = readEnd

converter toFd*(s: SocketHandle): Fd = s.Fd
converter toCint*(fd: Fd): cint = fd.cint
converter toCint*(id: Id): cint = id.cint
