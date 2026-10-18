# emsdk_env_locate.sh — sourced by build.sh and measure_wasm_build_flags.sh.
#
# If emcc is already on PATH (CI's setup-emsdk, or a shell that sourced emsdk_env.sh)
# it is used as is, and scripts/emcc-version-gate.sh checks it against the pin.
# Otherwise source the first emsdk_env.sh found, in this order:
#   $EMSDK_ENV (a path to an emsdk_env.sh)  >  $EMSDK/emsdk_env.sh
#   >  <repo>/emsdk  >  ~/emsdk  >  /usr/local/emsdk
# Nothing is hardcoded to one machine. Several emsdks side by side is fine: point
# EMSDK_ENV at the one you want (the gate refuses any version but the pin).
if ! command -v emcc &>/dev/null; then
    _locate_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    for _f in \
        "${EMSDK_ENV:-}" \
        "${EMSDK:+$EMSDK/emsdk_env.sh}" \
        "$_locate_root/emsdk/emsdk_env.sh" \
        "$HOME/emsdk/emsdk_env.sh" \
        "/usr/local/emsdk/emsdk_env.sh"; do
        if [ -n "$_f" ] && [ -f "$_f" ]; then
            # shellcheck disable=SC1090
            source "$_f" >/dev/null
            break
        fi
    done
    unset _locate_root _f
fi
