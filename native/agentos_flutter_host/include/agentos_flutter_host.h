/* C ABI for the product Flutter host over AgentOS KernelHost.
 * Not the BEAM Rustler NIF. See docs/native-host-ffi.md. */
#ifndef AGENTOS_FLUTTER_HOST_H
#define AGENTOS_FLUTTER_HOST_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque VM handle. 0 is invalid. */
typedef uint64_t aos_vm_t;

/* Tick state: 0 = runnable, 1 = waiting, 2 = exited */
enum {
  AOS_TICK_RUNNABLE = 0,
  AOS_TICK_WAITING = 1,
  AOS_TICK_EXITED = 2
};

/* All fallible functions return 0 on success, -1 on error (see aos_last_error). */

int aos_vm_boot(const uint8_t *kernel, size_t kernel_len, aos_vm_t *out_vm);

int aos_vm_tick(aos_vm_t vm, int32_t *out_state);

int aos_vm_send_input(aos_vm_t vm, const uint8_t *data, size_t len);

/* Copies up to cap bytes into buf. On success returns byte count (>= 0).
 * On error returns -1. */
int aos_vm_take_output(aos_vm_t vm, uint8_t *buf, size_t cap);

int aos_vm_close(aos_vm_t vm);

/* Run a shell command via the host structured exec path (KernelHost::exec).
 * On success: out_exit is set; up to stdout_cap/stderr_cap bytes are copied
 * and *stdout_len / *stderr_len report how many were written (may be truncated).
 * max_ticks bounds the host tick loop (0 => default 5_000_000).
 */
int aos_vm_exec(
    aos_vm_t vm,
    const char *cmd,
    uint64_t max_ticks,
    uint8_t *stdout_buf,
    size_t stdout_cap,
    size_t *stdout_len,
    uint8_t *stderr_buf,
    size_t stderr_cap,
    size_t *stderr_len,
    int32_t *out_exit);

/* NUL-terminated last error; valid until next API call on this thread. */
const char *aos_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* AGENTOS_FLUTTER_HOST_H */
