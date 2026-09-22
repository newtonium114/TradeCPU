#!/usr/bin/env bash
# Compiles and runs all TradeCPU testbenches with Icarus Verilog
# (iverilog + vvp), per spec Section 7 Stage 0.5's toolchain choice.
# Vivado is reserved for final checks only -- not used here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RTL_DIR="$ROOT_DIR/rtl"
SIM_DIR="$ROOT_DIR/sim"
BUILD_DIR="$SCRIPT_DIR/build"

mkdir -p "$BUILD_DIR"

FAIL=0

run_test () {
    local name="$1"
    shift
    echo "=== $name ==="
    if ! iverilog -g2005 -Wall -o "$BUILD_DIR/$name.vvp" "$@"; then
        echo "*** $name: COMPILE FAILED ***"
        FAIL=1
        return
    fi
    if ! (cd "$BUILD_DIR" && vvp "$name.vvp"); then
        echo "*** $name: SIMULATION FAILED ***"
        FAIL=1
    fi
    echo ""
}

run_test tb_register_file \
    "$RTL_DIR/register_file.v" \
    "$SIM_DIR/tb_register_file.v"

run_test tb_alu \
    "$RTL_DIR/alu.v" \
    "$SIM_DIR/tb_alu.v"

run_test tb_stage1_core \
    "$RTL_DIR/register_file.v" \
    "$RTL_DIR/alu.v" \
    "$RTL_DIR/control_unit.v" \
    "$RTL_DIR/tradecpu_core.v" \
    "$SIM_DIR/tb_stage1_core.v"

if [ "$FAIL" -ne 0 ]; then
    echo "One or more testbenches FAILED."
    exit 1
fi

echo "All Stage 1 testbenches completed successfully."
