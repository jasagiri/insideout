import std/atomics
import std/os
import std/unittest
import std/posix
template info*(arg: string) = echo "[INFO] ", arg
template debug*(arg: string) = discard
import pkg/cps
import insideout/runtimes
import insideout/eventqueue
import insideout/valgrind
import insideout/atomic/flags

type Server = ref object of Continuation
proc service() {.cps: Server.} =
  while true: coop()

const Service = whelp service

suite "signals":
  test "signal handling (halt via SIGTERM)":
    var mask: Sigset
    discard sigemptyset(mask)
    discard sigaddset(mask, SIGTERM)
    var oldMask: Sigset
    discard pthread_sigmask(SIG_BLOCK, mask, oldMask)
    let runtime = spawn(Service.call())
    os.sleep(100)
    discard posix.kill(posix.getpid(), SIGTERM)
    var finished = false
    for i in 1..20:
      if runtime.flags && <<Teardown:
        finished = true
        break
      os.sleep(100)
    check finished
