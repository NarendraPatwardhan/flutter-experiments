//! PERF-013 command stage breakdown.

use crate::buf::{fill_buf, AosBuf};
use crate::error::{clear_error, set_error};
use crate::table::with_host_mut;

#[no_mangle]
pub unsafe extern "C" fn aos_vm_set_perf_enabled(vm: u64, on: i32) -> i32 {
    clear_error();
    match with_host_mut(vm, |mut host| {
        host.set_perf_enabled(on != 0)
            .map_err(|e| format!("set_perf_enabled failed: {e:#}"))
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_scrub_perf(vm: u64) -> i32 {
    clear_error();
    match with_host_mut(vm, |mut host| {
        host.scrub_perf()
            .map_err(|e| format!("scrub_perf failed: {e:#}"))
    }) {
        Ok(()) => 0,
        Err(e) => {
            set_error(e);
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn aos_vm_take_command_perf(vm: u64, out: *mut AosBuf) -> i32 {
    clear_error();
    if out.is_null() {
        set_error("aos_vm_take_command_perf: null out");
        return -1;
    }
    match with_host_mut(vm, |mut host| Ok(host.take_command_perf())) {
        Ok(None) => {
            (*out).len = 0;
            0
        }
        Ok(Some(p)) => {
            // Fixed field order matching NIF command_perf_vec (17 fields).
            let s = format!(
                "{{\"wall_ms\":{},\"tick_ms\":{},\"pace_ms\":{},\"host_ticks\":{},\"host_runnable\":{},\"host_waiting\":{},\"kernel_ticks\":{},\"kernel_runnable\":{},\"kernel_waiting\":{},\"tasks_spawned\":{},\"pipes_created\":{},\"module_cache_hits\":{},\"module_cache_misses\":{},\"blocked_poll\":{},\"blocked_pipe\":{},\"blocked_wait_child\":{},\"kernel_memory_len\":{}}}",
                p.wall_ms,
                p.tick_ms,
                p.pace_ms,
                p.host_ticks,
                p.host_runnable,
                p.host_waiting,
                p.kernel_ticks,
                p.kernel_runnable,
                p.kernel_waiting,
                p.tasks_spawned,
                p.pipes_created,
                p.module_cache_hits,
                p.module_cache_misses,
                p.blocked_poll,
                p.blocked_pipe,
                p.blocked_wait_child,
                p.kernel_memory_len,
            );
            fill_buf(out, s.as_bytes())
        }
        Err(e) => {
            set_error(e);
            -1
        }
    }
}
