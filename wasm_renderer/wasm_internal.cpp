#include "wasm_internal.h"
#include <cstdio>
#include <cstring>
#include <string>

namespace pixelocity {
namespace wasm_internal {

WGPUStringView MakeStringView(const char* str) {
    WGPUStringView view;
    view.data = str;
    view.length = str ? strlen(str) : 0;
    return view;
}

uint32_t AlignUp(uint32_t value, uint32_t align) {
    return (value + align - 1u) & ~(align - 1u);
}

bool CheckLimit(const char* name, uint64_t have, uint64_t need, bool& ok) {
    printf("[WASM]   %-40s have=%llu need=%llu %s\n", name,
           static_cast<unsigned long long>(have),
           static_cast<unsigned long long>(need),
           have >= need ? "OK" : "INSUFFICIENT");
    if (have < need) ok = false;
    return have >= need;
}

bool ContainsWgslIncludeDirective(const char* wgsl) {
    if (!wgsl) return false;

    // Walk the source tracking comment state, so a directive that is only
    // mentioned in a comment does not trip the guard. WGSL block comments nest.
    const char* p = wgsl;
    bool lineStart = true;
    int blockDepth = 0;

    while (*p) {
        if (blockDepth > 0) {
            if (p[0] == '/' && p[1] == '*') { blockDepth++; p += 2; continue; }
            if (p[0] == '*' && p[1] == '/') { blockDepth--; p += 2; continue; }
            if (*p == '\n') lineStart = true;
            p++;
            continue;
        }

        if (p[0] == '/' && p[1] == '*') { blockDepth = 1; p += 2; continue; }
        if (p[0] == '/' && p[1] == '/') {
            while (*p && *p != '\n') p++;
            continue;
        }

        if (lineStart) {
            const char* q = p;
            while (*q == ' ' || *q == '\t') q++;
            if (std::strncmp(q, "#include", 8) == 0 && (q[8] == ' ' || q[8] == '\t')) {
                return true;
            }
        }

        lineStart = (*p == '\n');
        p++;
    }

    return false;
}

// Out of line on purpose: under -flto every inlined std::string append grew
// the .wasm by hundreds of bytes per call site.
__attribute__((noinline)) void AppendRaw(std::string& out, const char* s, size_t n) {
    out.append(s, n);
}

// The JSON helpers format by hand: snprintf reaches vfprintf's indirect write
// call, which makes ASYNCIFY instrument every caller (several KB of .wasm).
void AppendUInt(std::string& out, uint64_t v, int minDigits) {
    char buf[24];
    int i = sizeof(buf);
    do {
        buf[--i] = static_cast<char>('0' + v % 10);
        v /= 10;
    } while (v != 0 || static_cast<int>(sizeof(buf)) - i < minDigits);
    AppendRaw(out, buf + i, sizeof(buf) - static_cast<size_t>(i));
}

void AppendInt(std::string& out, int64_t v) {
    if (v < 0) {
        AppendLit(out, "-");
        AppendUInt(out, static_cast<uint64_t>(-(v + 1)) + 1u);
    } else {
        AppendUInt(out, static_cast<uint64_t>(v));
    }
}

void AppendJsonString(std::string& out, const char* s) {
    static const char kHex[] = "0123456789abcdef";
    AppendLit(out, "\"");
    const char* run = s ? s : "";
    const char* p = run;
    char esc[6] = {'\\', 'u', '0', '0', '0', '0'};
    for (; *p; ++p) {
        const unsigned char c = static_cast<unsigned char>(*p);
        if (c >= 0x20 && c != '"' && c != '\\') continue;
        AppendRaw(out, run, static_cast<size_t>(p - run));
        if (c == '"' || c == '\\') {
            const char pair[2] = {'\\', static_cast<char>(c)};
            AppendRaw(out, pair, 2);
        } else {
            esc[4] = kHex[c >> 4];
            esc[5] = kHex[c & 0xF];
            AppendRaw(out, esc, 6);
        }
        run = p + 1;
    }
    AppendRaw(out, run, static_cast<size_t>(p - run));
    AppendLit(out, "\"");
}

} // namespace wasm_internal
} // namespace pixelocity
