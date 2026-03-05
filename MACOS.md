# macOS Support in insideout

This document outlines the design decisions and implementation details for the macOS port of `insideout`.

## Futex Emulation using `ulock`

The core of `insideout` relies on Linux `futex(2)` for lightweight, address-based thread synchronization. macOS does not provide a public equivalent to this API.

### Design Choice: Undocumented `__ulock` APIs
We have chosen to use the undocumented system calls `__ulock_wait` and `__ulock_wake`.

- **Rationale**:
  - **Semantic Alignment**: These APIs are the closest match to Linux futexes, allowing synchronization directly on an atomic memory address without additional state.
  - **Performance**: Public alternatives like `pthread_cond` require a mutex and a condition variable, which would significantly increase the memory footprint and overhead of continuations.
  - **Precedent**: High-performance runtimes such as Go, Rust (std), and WebKit use these APIs on macOS for similar reasons.

- **Risks**:
  - **API Stability**: As these are undocumented, Apple may change their signature or availability in future OS updates.
  - **App Store Rejection**: Use of undocumented APIs is generally prohibited for apps distributed via the Mac App Store.
  - **Portability**: This implementation is specific to Darwin and may require updates for different architecture/OS versions.

### Fallback Strategy
If stability becomes an issue, a fallback using a process-wide `WaitTable` (mapping addresses to `pthread_cond`) could be implemented, though it would be slower and more complex.

## Event Loop and Signal Handling

### `kqueue` instead of `epoll`
The event queue has been ported to `kqueue(2)`.
- **Timers**: CPS-based `sleep` uses `EVFILT_TIMER`.
- **I/O**: Uses `EVFILT_READ` and `EVFILT_WRITE`.

### Signal Handling Emulation
Since macOS lacks `signalfd`, we emulate it using a dedicated signal thread:
1. `initSignalFd` creates a non-blocking pipe.
2. A hidden helper thread is started to wait for signals via `sigwait`.
3. When a signal is caught, the thread writes the signal number to the pipe.
4. The read end of the pipe is returned as the "Signal FD", making it compatible with the existing `EventQueue` architecture.

## Building and Testing

### Requirements
- **Memory Management**: `--mm:arc` or `--mm:orc` (arc preferred).
- **Compilation Flags**: `-d:useMalloc` is required as per `insideout` specifications.

### Verification
Specific tests for macOS have been added to the `tests/` directory:
- `tests/t00_futexes_macos.nim`
- `tests/t30_runtimes_macos.nim`
- `tests/t90_sleep_macos.nim`
- `tests/t99_signals_macos.nim`
