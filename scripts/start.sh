#!/usr/bin/env bash
# SPDX-License-Identifier: MulanPSL-2.0
#
# Start phase. Source ROS + colcon overlay + codegen PYTHONPATH, then
# exec the python module.
set -euo pipefail
PKG="${RBNX_PACKAGE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PKG"

ROS_DISTRO="${ROS_DISTRO:-humble}"
# shellcheck disable=SC1091
set +u; source "/opt/ros/${ROS_DISTRO}/setup.bash"; set -u

if [[ -f "$PKG/rbnx-build/ws/install/setup.bash" ]]; then
    # shellcheck disable=SC1091
    set +u; source "$PKG/rbnx-build/ws/install/setup.bash"; set -u
else
    echo "[llm_detect/start] ERR: colcon overlay missing — run scripts/build.sh" >&2
    exit 2
fi

# ── Direct PYTHONPATH / AMENT_PREFIX_PATH / LD_LIBRARY_PATH injection ──
# Same rationale as yolo_world_rbnx: colcon's idempotent prefix markers
# can silently NOT add our overlay's paths when another overlay is sourced.
GMSGS_PREFIX="$PKG/rbnx-build/ws/install/graspnet_msgs"
if [[ -d "$GMSGS_PREFIX" ]]; then
    case ":${AMENT_PREFIX_PATH:-}:" in
        *":${GMSGS_PREFIX}:"*) ;;
        *) export AMENT_PREFIX_PATH="${GMSGS_PREFIX}:${AMENT_PREFIX_PATH:-}" ;;
    esac
    for _site in \
        "$GMSGS_PREFIX"/local/lib/python*/dist-packages \
        "$GMSGS_PREFIX"/lib/python*/site-packages \
        "$GMSGS_PREFIX"/lib/python*/dist-packages
    do
        if [[ -d "$_site" ]]; then
            case ":${PYTHONPATH:-}:" in
                *":${_site}:"*) ;;
                *) export PYTHONPATH="${_site}:${PYTHONPATH:-}" ;;
            esac
        fi
    done
    unset _site
    for _libdir in \
        "$GMSGS_PREFIX"/lib \
        "$GMSGS_PREFIX"/local/lib
    do
        if [[ -d "$_libdir" ]]; then
            case ":${LD_LIBRARY_PATH:-}:" in
                *":${_libdir}:"*) ;;
                *) export LD_LIBRARY_PATH="${_libdir}:${LD_LIBRARY_PATH:-}" ;;
            esac
        fi
    done
    unset _libdir
fi
unset GMSGS_PREFIX

_source_overlay() {
    local f="$1"
    if [[ -f "$f" ]]; then
        echo "[llm_detect/start] sourcing extra overlay: $f" >&2
        # shellcheck disable=SC1090
        set +u; source "$f"; set -u
        return 0
    fi
    return 1
}

if [[ -n "${LLM_DETECT_EXTRA_OVERLAYS:-}" ]]; then
    IFS=':' read -ra _extras <<< "$LLM_DETECT_EXTRA_OVERLAYS"
    for f in "${_extras[@]}"; do _source_overlay "$f" || true; done
fi

if ! python3 -c "import graspnet_msgs.srv" 2>/dev/null; then
    echo "[llm_detect/start] WARN: graspnet_msgs not importable from \
own overlay — trying fallback paths" >&2
    for f in \
        "$HOME/lhw/grasp/driver/graspnet/install/setup.bash" \
        "$HOME/grasp/driver/graspnet/install/setup.bash" \
        "/home/syswonder/lhw/grasp/driver/graspnet/install/setup.bash"
    do
        _source_overlay "$f" && break || true
    done
fi

if ! python3 -c "import graspnet_msgs.srv" 2>&1 >/dev/null; then
    echo "[llm_detect/start] FATAL: cannot import graspnet_msgs.srv" >&2
    echo "[llm_detect/start] AMENT_PREFIX_PATH:" >&2
    printf '  %s\n' ${AMENT_PREFIX_PATH//:/ } >&2
    echo "[llm_detect/start] PYTHONPATH:" >&2
    printf '  %s\n' ${PYTHONPATH//:/ } >&2
    exit 3
fi
echo "[llm_detect/start] graspnet_msgs OK: $(python3 -c \
'import graspnet_msgs.srv as s; print(s.__file__)')" >&2

CODEGEN_PROTO="$PKG/rbnx-build/codegen/proto_gen"
CODEGEN_MCP="$PKG/rbnx-build/codegen/robonix_mcp_types"
if [[ ! -d "$CODEGEN_PROTO" || ! -d "$CODEGEN_MCP" ]]; then
    echo "[llm_detect/start] ERR: codegen output missing — run scripts/build.sh" >&2
    exit 2
fi
export PYTHONPATH="$CODEGEN_PROTO:$CODEGEN_MCP:$PKG:${PYTHONPATH:-}"
if ROBONIX_API="$(rbnx path robonix-api 2>/dev/null)"; then
    export PYTHONPATH="$ROBONIX_API:$PYTHONPATH"
fi

exec python3 -u -m llm_detect.main
