import std/atomics
import std/os
import std/unittest
template info*(arg: string) = echo "[INFO] ", arg
template debug*(arg: string) = discard
import pkg/cps
import insideout/runtimes
import insideout/mailboxes
import insideout/valgrind
import insideout/atomic/flags

type
  Server = ref object of Continuation
  Job = ref object

var began, recvd, ended: Atomic[bool]

proc unblocking(jobs: Mailbox[Job]) {.cps: Server.} =
  coop()
  began.store(true)
  var job: Job
  while true:
    case jobs.tryRecv(job)
    of Received:
      recvd.store(true)
    else:
      if not jobs.waitForPoppable: break
  ended.store(true)

const Unblocking = whelp unblocking

suite "runtimes":
  test "basic spawn and join":
    let jobs = newMailbox[Job]()
    var runtime = Unblocking.spawn(jobs)
    var job = Job()
    while Delivered != jobs.trySend(job): discard
    jobs.closeWrite()
    join runtime
    check ended.load
    check recvd.load
