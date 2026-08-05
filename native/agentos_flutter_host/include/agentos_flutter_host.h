/* C ABI over AgentOS KernelHost (wasmtime). Thin adapter — not a second host.
 * Sketch: docs/aos-c-api.md. Alpha: surface may break. */
#ifndef AGENTOS_FLUTTER_HOST_H
#define AGENTOS_FLUTTER_HOST_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AOS_API_VERSION 1

/* Opaque VM handle. 0 is invalid. */
typedef uint64_t aos_vm_t;

typedef enum {
  AOS_OK = 0,
  AOS_ERR = -1
} aos_status_t;

typedef enum {
  AOS_TICK_RUNNABLE = 0,
  AOS_TICK_WAITING = 1,
  AOS_TICK_EXITED = 2
} aos_tick_state_t;

typedef enum {
  AOS_NET_DENY = 0,
  AOS_NET_RELAY = 1,
  AOS_NET_REAL = 2
} aos_net_mode_t;

typedef enum {
  AOS_CAP_DENY = 0,
  AOS_CAP_RELAY = 1
} aos_cap_mode_t;

typedef enum {
  AOS_STREAM_STDOUT = 1,
  AOS_STREAM_STDERR = 2,
  AOS_STREAM_LOG = 4
} aos_stream_mask_t;

/* Caller-owned byte buffer: set ptr/cap; on success len = written.
 * On AOS_ERR with overflow, len may be set to required size when documented. */
typedef struct {
  uint8_t *ptr;
  size_t cap;
  size_t len;
} aos_buf_t;

/* Library-allocated blob; free with aos_bytes_free. */
typedef struct {
  uint8_t *ptr;
  size_t len;
} aos_bytes_t;

typedef struct {
  size_t size; /* sizeof(aos_boot_opts_t) */
  const uint8_t *base_image;
  size_t base_image_len;
  const uint8_t *const *layers;
  const size_t *layer_lens;
  size_t layer_count;
  int deterministic;
  int has_contract;
  int32_t contract_tier;
  int32_t contract_budget_mib;
  int64_t contract_fuel;
  uint32_t workers;
  aos_net_mode_t net;
  aos_cap_mode_t host_call;
  int host_call_sidecar_only;
  aos_cap_mode_t persist;
  aos_cap_mode_t tool_approval;
  const uint8_t *connections_blob;
  size_t connections_len;
  const uint8_t *connection_policies_blob;
  size_t connection_policies_len;
} aos_boot_opts_t;

typedef struct {
  size_t size; /* sizeof(aos_exec_opts_t) */
  const char *cwd;
  const uint8_t *env_blob;
  size_t env_blob_len;
  const uint8_t *stdin_data;
  size_t stdin_len;
  uint64_t max_ticks; /* 0 = default */
} aos_exec_opts_t;

typedef struct {
  size_t size;
  uint64_t bytes_written;
  int32_t exit_code; /* INT32_MIN = none */
  int at_prompt;
  uint32_t workers;
  int has_worker_entry;
  uint32_t inflight_egress;
  uint32_t pending_commits;
} aos_vm_status_t;

typedef struct {
  uint64_t size;
  int is_dir;
  int is_symlink;
  uint32_t nlink;
  uint32_t mode;
} aos_stat_t;

/* ---- version / error / free ---- */
int aos_api_version(void);
const char *aos_version(void);
const char *aos_last_error(void);
void aos_bytes_free(aos_bytes_t *b);

/* ---- lifecycle (compat + extended) ---- */
/* Compat: single base image, deny-default caps, tick toward prompt like before. */
int aos_vm_boot(
    const uint8_t *kernel,
    size_t kernel_len,
    const uint8_t *image,
    size_t image_len,
    aos_vm_t *out_vm);

int aos_vm_boot_ex(
    const uint8_t *kernel,
    size_t kernel_len,
    const aos_boot_opts_t *opts,
    aos_vm_t *out_vm);

int aos_vm_restore(
    const uint8_t *kernel,
    size_t kernel_len,
    const uint8_t *snapshot,
    size_t snapshot_len,
    const uint8_t *base_snapshot,
    size_t base_snapshot_len,
    const aos_boot_opts_t *opts,
    aos_vm_t *out_vm);

int aos_vm_close(aos_vm_t vm);

/* ---- terminal I/O ---- */
int aos_vm_tick(aos_vm_t vm, int32_t *out_state);
int aos_vm_tick_n(aos_vm_t vm, uint32_t n, int32_t *out_state);
int aos_vm_send_input(aos_vm_t vm, const uint8_t *data, size_t len);
/* Returns byte count (>=0) or -1. If cap==0, returns pending length. */
int aos_vm_take_output(aos_vm_t vm, uint8_t *buf, size_t cap);
int aos_vm_take_output_ex(aos_vm_t vm, int stream_mask, aos_buf_t *out);
int aos_vm_status(aos_vm_t vm, aos_vm_status_t *out);

/* ---- process ---- */
/* Compat exec: max_ticks 0 => default; opts unavailable (use aos_vm_exec_ex). */
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

int aos_vm_exec_ex(
    aos_vm_t vm,
    const char *cmd,
    const aos_exec_opts_t *opts,
    aos_buf_t *stdout_b,
    aos_buf_t *stderr_b,
    int32_t *out_exit);

int aos_vm_run(
    aos_vm_t vm,
    const char *program,
    const char *const *argv,
    size_t argc,
    const aos_exec_opts_t *opts,
    aos_buf_t *stdout_b,
    aos_buf_t *stderr_b,
    int32_t *out_exit);

int aos_vm_exec_start(
    aos_vm_t vm,
    const char *cmd,
    const aos_exec_opts_t *opts,
    int64_t *out_job);

int aos_vm_run_start(
    aos_vm_t vm,
    const char *program,
    const char *const *argv,
    size_t argc,
    const aos_exec_opts_t *opts,
    int64_t *out_job);

/* out_done: 0 still running, 1 finished. When finished, exit/stdout/stderr filled. */
int aos_vm_exec_poll(
    aos_vm_t vm,
    int64_t job,
    int *out_done,
    int32_t *out_exit,
    aos_buf_t *stdout_b,
    aos_buf_t *stderr_b);

int aos_vm_exec_stdout_peek(aos_vm_t vm, int64_t job, aos_buf_t *out);
int aos_vm_exec_cancel(aos_vm_t vm, int64_t job);

/* out_encoded: implementation-defined length-prefixed candidate list. */
int aos_vm_autocomplete(
    aos_vm_t vm,
    const char *source,
    size_t cursor_byte,
    const aos_exec_opts_t *opts,
    aos_buf_t *out_encoded);

/* ---- services / FS ---- */
int aos_vm_svc_call(
    aos_vm_t vm,
    const char *service,
    const uint8_t *req,
    size_t req_len,
    int32_t *out_status,
    aos_buf_t *out_body);

int aos_vm_read_file(aos_vm_t vm, const char *path, aos_buf_t *out);
int aos_vm_write_file(
    aos_vm_t vm, const char *path, const uint8_t *data, size_t len);
int aos_vm_readdir(aos_vm_t vm, const char *path, aos_buf_t *out_encoded);
int aos_vm_stat(aos_vm_t vm, const char *path, aos_stat_t *out);
int aos_vm_readlink(aos_vm_t vm, const char *path, aos_buf_t *out);
int aos_vm_mkdir(aos_vm_t vm, const char *path);
int aos_vm_unlink(aos_vm_t vm, const char *path);
int aos_vm_chmod(aos_vm_t vm, const char *path, uint32_t mode);
int aos_vm_symlink(aos_vm_t vm, const char *target, const char *link_path);
int aos_vm_mount(aos_vm_t vm, const char *path, int read_only);
int aos_vm_unmount(aos_vm_t vm, const char *path);

/* ---- snapshot / layer ---- */
int aos_vm_snapshot(aos_vm_t vm, aos_bytes_t *out);
int aos_vm_snapshot_into(aos_vm_t vm, aos_buf_t *out);
int aos_vm_snapshot_incremental(
    aos_vm_t vm,
    const uint8_t *base,
    size_t base_len,
    aos_bytes_t *out);
int aos_vm_commit_layer(
    aos_vm_t vm, aos_bytes_t *out_tar, aos_buf_t *out_digest_hex);

/* ---- relay (pull + respond; frames are opaque length-prefixed UTF-8/JSON-ish) ---- */
int aos_vm_relay_next(aos_vm_t vm, aos_buf_t *out_frame);
int aos_vm_relay_next_sidecar(aos_vm_t vm, aos_buf_t *out_frame);
int aos_vm_relay_http_respond(
    aos_vm_t vm,
    int64_t handle,
    int ok,
    const uint8_t *head,
    size_t head_len,
    const uint8_t *body,
    size_t body_len);
int aos_vm_relay_host_call_respond(
    aos_vm_t vm,
    int64_t handle,
    int ok,
    const uint8_t *result,
    size_t result_len);
int aos_vm_relay_persist_respond(
    aos_vm_t vm,
    int64_t handle,
    int ok,
    const uint8_t *body,
    size_t body_len);
int aos_vm_relay_tool_approval_respond(
    aos_vm_t vm, int64_t handle, int allow, int remember_session);
int aos_vm_relay_ws_open(aos_vm_t vm, int64_t handle, int ok);
int aos_vm_relay_ws_push(
    aos_vm_t vm, int64_t handle, const uint8_t *data, size_t len);
int aos_vm_relay_ws_close(aos_vm_t vm, int64_t handle);

/* ---- catalog / perf ---- */
int aos_vm_inject_catalog(
    aos_vm_t vm,
    const uint8_t *compiler_wasm,
    size_t compiler_len,
    uint64_t generation,
    const uint8_t *catalog_blob,
    size_t catalog_len,
    aos_buf_t *out_status_encoded);
int aos_vm_set_perf_enabled(aos_vm_t vm, int on);
int aos_vm_scrub_perf(aos_vm_t vm);
int aos_vm_take_command_perf(aos_vm_t vm, aos_buf_t *out_encoded);

#ifdef __cplusplus
}
#endif

#endif /* AGENTOS_FLUTTER_HOST_H */
