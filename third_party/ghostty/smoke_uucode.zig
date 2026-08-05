//! Smoke: compile-link against the pin-built uucode module.
const uucode = @import("uucode");

pub fn main() void {
    // Touch a real API so the module is fully analyzed.
    _ = uucode.get(.width, 'A');
}
