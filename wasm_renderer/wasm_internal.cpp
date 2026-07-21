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

// Find the @workgroup_size attribute attached to compute entry point `entry`
// (the renderer only ever dispatches `main`, so a 1D helper kernel declared
// before `main` must not win). Returns nullptr if no entry-point-attached
// match is found.
static const char* FindWorkgroupSizeForEntry(const char* wgsl, const char* entry) {
    const size_t entryLen = strlen(entry);
    const char* p = wgsl;
    while ((p = strstr(p, "@workgroup_size")) != nullptr) {
        const char* fn = strstr(p + 15, "fn ");
        if (fn) {
            const char* name = fn + 3;
            while (*name == ' ' || *name == '\t') name++;
            if (strncmp(name, entry, entryLen) == 0) {
                const char next = name[entryLen];
                if (next == '(' || next == ' ' || next == '\t' ||
                    next == '\n' || next == '\r') {
                    return p;
                }
            }
        }
        p += 15;
    }
    return nullptr;
}

void ParseWorkgroupSize(const char* wgslCode, uint32_t& x, uint32_t& y) {
    x = 16;
    y = 16;
    if (!wgslCode) return;

    // Prefer the @workgroup_size belonging to entry point `main` (the only
    // entry point the renderer dispatches); fall back to the first one.
    const char* ws = FindWorkgroupSizeForEntry(wgslCode, "main");
    if (!ws) {
        const char* p = strstr(wgslCode, "@compute");
        if (!p) return;
        ws = strstr(p + 8, "@workgroup_size");
        if (!ws) return;
    }

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

static bool HasGroup0Binding(const char* wgsl, uint32_t binding) {
    if (!wgsl) return false;
    char needle[32];
    std::snprintf(needle, sizeof(needle), "@binding(%u)", binding);
    const char* p = wgsl;
    while ((p = std::strstr(p, "@group(0)")) != nullptr) {
        const char* bindPos = std::strstr(p, needle);
        if (bindPos && bindPos < p + 128) {
            return true;
        }
        p += 8;
    }
    return false;
}

static const char* BindingVarName(const char* wgsl, uint32_t binding) {
    if (!wgsl) return nullptr;
    char needle[32];
    std::snprintf(needle, sizeof(needle), "@binding(%u)", binding);
    const char* bindPos = std::strstr(wgsl, needle);
    if (!bindPos) return nullptr;
    const char* varPos = std::strstr(bindPos, "var");
    if (!varPos || varPos > bindPos + 128) return nullptr;
    const char* p = varPos + 3;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    if (*p == '<') {
        p = std::strchr(p, '>');
        if (!p) return nullptr;
        p++;
        while (*p == ' ' || *p == '\t') p++;
    }
    if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || *p == '_')) {
        return nullptr;
    }
    return p;
}

static size_t CountWordRefs(const char* wgsl, const char* nameStart) {
    if (!wgsl || !nameStart) return 0;
    size_t nameLen = 0;
    while (nameStart[nameLen] &&
           ((nameStart[nameLen] >= 'a' && nameStart[nameLen] <= 'z') ||
            (nameStart[nameLen] >= 'A' && nameStart[nameLen] <= 'Z') ||
            (nameStart[nameLen] >= '0' && nameStart[nameLen] <= '9') ||
            nameStart[nameLen] == '_')) {
        nameLen++;
    }
    if (nameLen == 0) return 0;

    size_t count = 0;
    const char* p = wgsl;
    while ((p = std::strstr(p, nameStart)) != nullptr) {
        bool leftOk = (p == wgsl) || !((p[-1] >= 'a' && p[-1] <= 'z') ||
                                       (p[-1] >= 'A' && p[-1] <= 'Z') ||
                                       (p[-1] >= '0' && p[-1] <= '9') ||
                                       p[-1] == '_');
        bool rightOk = (p[nameLen] == '\0') || !((p[nameLen] >= 'a' && p[nameLen] <= 'z') ||
                                                (p[nameLen] >= 'A' && p[nameLen] <= 'Z') ||
                                                (p[nameLen] >= '0' && p[nameLen] <= '9') ||
                                                p[nameLen] == '_');
        if (leftOk && rightOk) count++;
        p += nameLen;
    }
    return count;
}

static bool UsedBeyondDeclaration(const char* wgsl, uint32_t binding) {
    if (!HasGroup0Binding(wgsl, binding)) return false;
    const char* nameStart = BindingVarName(wgsl, binding);
    if (!nameStart) return true; // conservative
    return CountWordRefs(wgsl, nameStart) > 1;
}

ShaderBindingUsage AnalyzeShaderBindings(const char* wgslCode) {
    ShaderBindingUsage usage;
    if (!wgslCode) return usage;
    usage.writesDataA = UsedBeyondDeclaration(wgslCode, 7);
    usage.writesDataB = UsedBeyondDeclaration(wgslCode, 8);
    usage.readsDataC = UsedBeyondDeclaration(wgslCode, 9);
    usage.usesHistory = UsedBeyondDeclaration(wgslCode, 13);
    return usage;
}

} // namespace wasm_internal
} // namespace pixelocity
