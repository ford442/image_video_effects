//! GPU-less WGSL validation, compiled to wasm32 so Node scripts, CI and the
//! browser all run the same naga the host `naga` CLI runs.
//!
//! Deliberately no wasm-bindgen: the ABI below is small enough to hand-write,
//! which keeps `wasm-pack` off CI and off agent VMs. The JS side lives in
//! `public/wasm/naga_wasm.js` and is the only supported caller.
//!
//! ABI
//!   wgsl_alloc(len) -> ptr        caller writes `len` UTF-8 bytes at ptr
//!   wgsl_validate(ptr, len) -> i32   0 = valid, 1 = parse error, 2 = validation error
//!   glsl_to_wgsl(ptr, len, stage) -> i32   GLSL 450 in, WGSL out (Shadertoy import)
//!   wgsl_result_ptr() / wgsl_result_len()   JSON result of the last call
//!   wgsl_free(ptr, len)
//!
//! The result buffer is owned by the module and is overwritten by the next
//! call, so JS must copy it out before calling again.

use std::alloc::{alloc, dealloc, Layout};
use std::cell::RefCell;

thread_local! {
    static RESULT: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

fn layout(len: usize) -> Layout {
    // len.max(1): a zero-size layout is UB to allocate.
    Layout::from_size_align(len.max(1), 1).expect("valid layout")
}

#[no_mangle]
pub extern "C" fn wgsl_alloc(len: usize) -> *mut u8 {
    unsafe { alloc(layout(len)) }
}

#[no_mangle]
pub extern "C" fn wgsl_free(ptr: *mut u8, len: usize) {
    unsafe { dealloc(ptr, layout(len)) }
}

#[no_mangle]
pub extern "C" fn wgsl_result_ptr() -> *const u8 {
    RESULT.with(|r| r.borrow().as_ptr())
}

#[no_mangle]
pub extern "C" fn wgsl_result_len() -> usize {
    RESULT.with(|r| r.borrow().len())
}

/// Returns 0 = valid, 1 = parse error, 2 = validation error.
/// The JSON diagnostic is left in the result buffer either way.
#[no_mangle]
pub extern "C" fn wgsl_validate(ptr: *const u8, len: usize) -> i32 {
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
    let src = match std::str::from_utf8(bytes) {
        Ok(s) => s,
        Err(e) => {
            set_result(&json_error("encoding", &format!("source is not UTF-8: {e}"), 0, 0));
            return 1;
        }
    };

    match naga::front::wgsl::parse_str(src) {
        Err(e) => {
            let (line, pos) = e
                .location(src)
                .map(|l| (l.line_number, l.line_position))
                .unwrap_or((0, 0));
            set_result(&json_error("parse", &e.emit_to_string(src), line, pos));
            1
        }
        Ok(module) => {
            let mut validator = naga::valid::Validator::new(
                naga::valid::ValidationFlags::all(),
                naga::valid::Capabilities::default(),
            );
            match validator.validate(&module) {
                Ok(_) => {
                    set_result(br#"{"ok":true}"#);
                    0
                }
                Err(e) => {
                    let (line, pos) = e
                        .spans()
                        .next()
                        .map(|(span, _)| {
                            let l = span.location(src);
                            (l.line_number, l.line_position)
                        })
                        .unwrap_or((0, 0));
                    set_result(&json_error("validate", &e.emit_to_string(src), line, pos));
                    2
                }
            }
        }
    }
}

/// Translates Vulkan-flavoured GLSL 450 to WGSL. `stage`: 0 = vertex,
/// 1 = fragment, 2 = compute.
///
/// Returns 0 = translated, 1 = parse error, 2 = validation error,
/// 3 = WGSL writer error. On success the result buffer holds
/// `{"ok":true,"wgsl":"..."}`; otherwise the same diagnostic shape as
/// `wgsl_validate`.
#[no_mangle]
pub extern "C" fn glsl_to_wgsl(ptr: *const u8, len: usize, stage: u32) -> i32 {
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
    let src = match std::str::from_utf8(bytes) {
        Ok(s) => s,
        Err(e) => {
            set_result(&json_error("encoding", &format!("source is not UTF-8: {e}"), 0, 0));
            return 1;
        }
    };
    let stage = match stage {
        0 => naga::ShaderStage::Vertex,
        2 => naga::ShaderStage::Compute,
        _ => naga::ShaderStage::Fragment,
    };

    let module = match naga::front::glsl::Frontend::default()
        .parse(&naga::front::glsl::Options::from(stage), src)
    {
        Ok(module) => module,
        Err(errors) => {
            let (line, pos) = errors
                .errors
                .first()
                .and_then(|e| e.location(src))
                .map(|l| (l.line_number, l.line_position))
                .unwrap_or((0, 0));
            set_result(&json_error("parse", &errors.emit_to_string(src), line, pos));
            return 1;
        }
    };

    let mut validator = naga::valid::Validator::new(
        naga::valid::ValidationFlags::all(),
        naga::valid::Capabilities::default(),
    );
    let info = match validator.validate(&module) {
        Ok(info) => info,
        Err(e) => {
            let (line, pos) = e
                .spans()
                .next()
                .map(|(span, _)| {
                    let l = span.location(src);
                    (l.line_number, l.line_position)
                })
                .unwrap_or((0, 0));
            set_result(&json_error("validate", &e.emit_to_string(src), line, pos));
            return 2;
        }
    };

    match naga::back::wgsl::write_string(&module, &info, naga::back::wgsl::WriterFlags::empty()) {
        Ok(wgsl) => {
            let mut out = String::with_capacity(wgsl.len() + 32);
            out.push_str(r#"{"ok":true,"wgsl":""#);
            escape_into(&wgsl, &mut out);
            out.push_str(r#""}"#);
            set_result(out.as_bytes());
            0
        }
        Err(e) => {
            set_result(&json_error("write", &e.to_string(), 0, 0));
            3
        }
    }
}

fn set_result(bytes: &[u8]) {
    RESULT.with(|r| {
        let mut buf = r.borrow_mut();
        buf.clear();
        buf.extend_from_slice(bytes);
    });
}

fn json_error(kind: &str, message: &str, line: u32, pos: u32) -> Vec<u8> {
    let mut out = String::with_capacity(message.len() + 64);
    out.push_str(r#"{"ok":false,"kind":""#);
    escape_into(kind, &mut out);
    out.push_str(r#"","message":""#);
    escape_into(message, &mut out);
    out.push_str(&format!(r#"","line":{line},"pos":{pos}}}"#));
    out.into_bytes()
}

fn escape_into(s: &str, out: &mut String) {
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
}
