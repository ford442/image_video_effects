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
//!   wgsl_reflect(ptr, len) -> i32   bindings + entry points (Graph Lab port inference)
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

/// Resource reflection for the Graph Lab's port inference: every global with a
/// `@group/@binding`, every entry point, and — when the module validates — which
/// bindings each entry point actually uses.
///
/// Returns 0 = reflected and valid, 1 = parse error (diagnostic only),
/// 2 = reflected but the module does not validate (no `uses`). On 0 / 2 the
/// result buffer holds
/// `{"ok":true,"valid":bool,"bindings":[…],"entryPoints":[…]}` where a binding is
/// `{"group","binding","name","resource","access","dim","arrayed"}` and an entry
/// point `{"name","stage","workgroupSize":[x,y,z],"uses":[[group,binding,flags],…]}`
/// (`flags` = naga `GlobalUse` bits: 1 read, 2 write, 4 query, 8 atomic)
/// (`uses` is omitted when the module does not validate).
#[no_mangle]
pub extern "C" fn wgsl_reflect(ptr: *const u8, len: usize) -> i32 {
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
    let src = match std::str::from_utf8(bytes) {
        Ok(s) => s,
        Err(e) => {
            set_result(&json_error("encoding", &format!("source is not UTF-8: {e}"), 0, 0));
            return 1;
        }
    };
    let module = match naga::front::wgsl::parse_str(src) {
        Ok(module) => module,
        Err(e) => {
            let (line, pos) = e
                .location(src)
                .map(|l| (l.line_number, l.line_position))
                .unwrap_or((0, 0));
            set_result(&json_error("parse", &e.emit_to_string(src), line, pos));
            return 1;
        }
    };
    let info = naga::valid::Validator::new(
        naga::valid::ValidationFlags::all(),
        naga::valid::Capabilities::all(),
    )
    .validate(&module)
    .ok();

    let mut out = String::with_capacity(1024);
    out.push_str(r#"{"ok":true,"valid":"#);
    out.push_str(if info.is_some() { "true" } else { "false" });
    out.push_str(r#","bindings":["#);
    let mut first = true;
    for (_, var) in module.global_variables.iter() {
        let Some(rb) = &var.binding else { continue };
        if !first {
            out.push(',');
        }
        first = false;
        let (resource, access, dim, arrayed) = describe_resource(&module, var);
        out.push_str(&format!(r#"{{"group":{},"binding":{},"name":""#, rb.group, rb.binding));
        escape_into(var.name.as_deref().unwrap_or(""), &mut out);
        out.push_str(&format!(
            r#"","resource":"{resource}","access":"{access}","dim":"{dim}","arrayed":{arrayed}}}"#
        ));
    }
    out.push_str(r#"],"entryPoints":["#);
    for (i, ep) in module.entry_points.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let stage = match ep.stage {
            naga::ShaderStage::Vertex => "vertex",
            naga::ShaderStage::Fragment => "fragment",
            naga::ShaderStage::Compute => "compute",
            _ => "other",
        };
        out.push_str(r#"{"name":""#);
        escape_into(&ep.name, &mut out);
        let [x, y, z] = ep.workgroup_size;
        out.push_str(&format!(r#"","stage":"{stage}","workgroupSize":[{x},{y},{z}]"#));
        if let Some(info) = &info {
            let fi = info.get_entry_point(i);
            out.push_str(r#","uses":["#);
            let mut first_use = true;
            for (handle, var) in module.global_variables.iter() {
                let Some(rb) = &var.binding else { continue };
                if fi[handle].is_empty() {
                    continue;
                }
                if !first_use {
                    out.push(',');
                }
                first_use = false;
                out.push_str(&format!("[{},{},{}]", rb.group, rb.binding, fi[handle].bits()));
            }
            out.push(']');
        }
        out.push('}');
    }
    out.push_str("]}");
    set_result(out.as_bytes());
    if info.is_some() { 0 } else { 2 }
}

/// (resource, access, dim, arrayed) of one bound global.
fn describe_resource(
    module: &naga::Module,
    var: &naga::GlobalVariable,
) -> (&'static str, &'static str, &'static str, bool) {
    use naga::{AddressSpace, ImageClass, ImageDimension, TypeInner};
    let mut inner = &module.types[var.ty].inner;
    if let TypeInner::BindingArray { base, .. } = inner {
        inner = &module.types[*base].inner;
    }
    match inner {
        TypeInner::Image { dim, arrayed, class } => {
            let dim = match dim {
                ImageDimension::D1 => "1d",
                ImageDimension::D2 => "2d",
                ImageDimension::D3 => "3d",
                ImageDimension::Cube => "cube",
            };
            match class {
                ImageClass::Storage { access, .. } => {
                    let a = if access.contains(naga::StorageAccess::LOAD | naga::StorageAccess::STORE) {
                        "read_write"
                    } else if access.contains(naga::StorageAccess::STORE) {
                        "write"
                    } else {
                        "read"
                    };
                    ("storage_texture", a, dim, *arrayed)
                }
                ImageClass::Depth { .. } => ("depth_texture", "read", dim, *arrayed),
                _ => ("texture", "read", dim, *arrayed),
            }
        }
        TypeInner::Sampler { .. } => ("sampler", "read", "", false),
        _ => match var.space {
            AddressSpace::Uniform => ("uniform", "read", "", false),
            AddressSpace::Storage { access } => {
                let a = if access.contains(naga::StorageAccess::STORE) { "read_write" } else { "read" };
                ("storage", a, "", false)
            }
            _ => ("other", "read", "", false),
        },
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
