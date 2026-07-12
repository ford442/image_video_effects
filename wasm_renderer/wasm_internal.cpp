#include "wasm_internal.h"
#include <cstdio>
#include <cstring>

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

void ParseWorkgroupSize(const char* wgslCode, uint32_t& x, uint32_t& y) {
    x = 16;
    y = 16;
    if (!wgslCode) return;

    const char* p = strstr(wgslCode, "@compute");
    if (!p) return;

    const char* ws = strstr(p + 8, "@workgroup_size");
    if (!ws) return;

    const char* r = ws + 15;
    while (*r == ' ' || *r == '\t' || *r == '\n' || *r == '\r') r++;
    if (*r != '(') return;
    r++;

    while (*r == ' ' || *r == '\t') r++;
    if (*r < '0' || *r > '9') return;
    uint32_t nx = 0;
    while (*r >= '0' && *r <= '9') nx = nx * 10 + static_cast<uint32_t>(*r++ - '0');

    while (*r == ' ' || *r == '\t') r++;
    if (*r != ',') {
        x = nx;
        y = 1;
        return;
    }
    r++;

    while (*r == ' ' || *r == '\t') r++;
    if (*r < '0' || *r > '9') {
        x = nx;
        return;
    }
    uint32_t ny = 0;
    while (*r >= '0' && *r <= '9') ny = ny * 10 + static_cast<uint32_t>(*r++ - '0');

    x = nx;
    y = ny;
}

} // namespace wasm_internal
} // namespace pixelocity
