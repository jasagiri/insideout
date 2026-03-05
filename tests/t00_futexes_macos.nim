import std/atomics
import std/posix
import std/unittest
import insideout/futexes

suite "futexes":
  test "wait() and waitMask()":
    var x: Atomic[uint32]
    store(x, 1, order = moSequentiallyConsistent)
    # タイムアウトの確認
    check checkWait(wait(x, 1, timeout = 0.01)) == ETIMEDOUT
    # 値の不一致（EAGAIN）の確認
    store(x, 2, order = moSequentiallyConsistent)
    check checkWait(wait(x, 1, timeout = 0.01)) == EAGAIN
    # waitMaskの不一致確認
    let res3 = waitMask(x, 2, 4)
    check checkWait(res3) == EAGAIN
