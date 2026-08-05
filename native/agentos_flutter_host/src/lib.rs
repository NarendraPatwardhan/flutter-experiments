//! Product C ABI over AgentOS `host::KernelHost` (wasmtime).
//! Modular surface — see docs/aos-c-api.md and include/agentos_flutter_host.h.

mod boot;
mod buf;
mod catalog;
mod error;
mod exec;
mod fs;
mod perf;
mod relay;
mod snapshot;
mod table;
mod tty;

// Re-export C entry points so the shared library exposes them (modules use #[no_mangle]).
// No additional code here — keep lib.rs thin.
