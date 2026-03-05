import std/atomics
import std/os
import std/unittest
import std/times
template info*(arg: string) = echo "[INFO] ", arg
template debug*(arg: string) = discard
import pkg/cps
import insideout/runtimes
import insideout/eventqueue
import insideout/valgrind
import insideout/atomic/flags

type Server = ref object of Continuation
var ended: Atomic[bool]
var startTime, endTime: float

proc sleeper(eq: EventQueue) {.cps: Server.} =
  startTime = epochTime()
  sleep(eq, 0.5)
  endTime = epochTime()
  ended.store(true)

const Sleeper = whelp sleeper

suite "sleep":
  test "cps sleep on macOS":
    var eq: EventQueue
    init eq
    let runtime = spawn(Sleeper.call(eq))
    var events: array[1, EventInfo]
    let n = eq.wait(events, timeout = 2.0)
    if n > 0:
      eq.run(events, n)
      eq.pruneOneShots(events, n)
    check ended.load()
    if ended.load():
      check endTime - startTime >= 0.4
    halt runtime
    join runtime
