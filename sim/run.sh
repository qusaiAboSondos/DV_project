#!/usr/bin/env bash
# =============================================================================
# run.sh - Compile and simulate the BIRD UVM testbench
#
# Usage:
#   ./run.sh [TEST_NAME] [TOOL] [EXTRA_PLUSARGS...]
#
#   TEST_NAME  : UVM test to run (default: rand_test)
#   TOOL       : vcs | questa (default: vcs)
#
# Examples:
#   ./run.sh
#   ./run.sh local_basic_test
#   ./run.sh remote_outoforder_test vcs +WAVES
#   ./run.sh drop_conditions_test questa
#
# Available tests:
#   bird_base_test
#   local_basic_test
#   remote_basic_test
#   remote_outoforder_test
#   drop_conditions_test
#   backpressure_test
#   rand_test
# =============================================================================

set -e

# --- Configuration -----------------------------------------------------------
TEST_NAME="${1:-rand_test}"
TOOL="${2:-vcs}"
shift 2 2>/dev/null || true
EXTRA_ARGS="$@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(dirname "${SCRIPT_DIR}")"
DUT_DIR="${PROJ_DIR}/dut"
TB_DIR="${PROJ_DIR}/tb"
SIM_DIR="${SCRIPT_DIR}"

UVM_HOME="${UVM_HOME:-/tools/uvm/uvm-1.2}"
UVM_LIB="${UVM_LIB:-${UVM_HOME}/src}"

echo "========================================================"
echo "  BIRD UVM Testbench"
echo "  Test     : ${TEST_NAME}"
echo "  Tool     : ${TOOL}"
echo "  Proj dir : ${PROJ_DIR}"
echo "========================================================"

# --- Source file lists -------------------------------------------------------
DUT_FILES="${DUT_DIR}/bird.sv"

TB_FILES="\
    ${TB_DIR}/bird_if.sv \
    ${TB_DIR}/bird_pkg.sv \
    ${TB_DIR}/tb_top.sv"

# =============================================================================
# VCS Flow
# =============================================================================
if [ "${TOOL}" == "vcs" ]; then

    VCS="${VCS_HOME:-vcs}"
    SIMV="./simv"
    WORK_DIR="${SIM_DIR}/vcs_work"
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"

    echo ""
    echo "--- Compiling with VCS ---"
    ${VCS} \
        -full64 \
        -sverilog \
        -ntb_opts uvm-1.2 \
        +define+UVM_NO_DEPRECATED \
        +define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR \
        -timescale=1ns/1ps \
        +incdir+"${TB_DIR}" \
        +incdir+"${UVM_LIB}" \
        -f /dev/stdin \
        -o simv \
        -debug_access+all \
        -l compile.log << EOF
${DUT_FILES}
${TB_FILES}
EOF

    echo ""
    echo "--- Running simulation: ${TEST_NAME} ---"
    ${SIMV} \
        +UVM_TESTNAME="${TEST_NAME}" \
        +UVM_VERBOSITY=UVM_MEDIUM \
        +UVM_TR_RECORD \
        +UVM_LOG_RECORD \
        ${EXTRA_ARGS} \
        -l "${TEST_NAME}.log"

    echo ""
    echo "--- Log: ${WORK_DIR}/${TEST_NAME}.log ---"

# =============================================================================
# Questa / ModelSim Flow
# =============================================================================
elif [ "${TOOL}" == "questa" ]; then

    VLIB="${QUESTA_HOME:-vlib}"
    VMAP="${QUESTA_HOME:-vmap}"
    VLOG="${QUESTA_HOME:-vlog}"
    VSIM="${QUESTA_HOME:-vsim}"
    WORK_DIR="${SIM_DIR}/questa_work"
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"

    echo ""
    echo "--- Setting up Questa library ---"
    vlib work
    vmap work work

    echo ""
    echo "--- Compiling with Questa/vlog ---"
    vlog \
        -sv \
        -mfcu \
        +define+UVM_NO_DEPRECATED \
        +define+QUESTA \
        -timescale "1ns/1ps" \
        +incdir+"${TB_DIR}" \
        +incdir+"${UVM_LIB}" \
        -L uvm \
        ${DUT_FILES} \
        ${TB_FILES} \
        -l compile.log

    echo ""
    echo "--- Running simulation: ${TEST_NAME} ---"
    vsim \
        -c \
        -lib work \
        -sv_lib "${UVM_HOME}/lib/uvm_dpi" \
        +UVM_TESTNAME="${TEST_NAME}" \
        +UVM_VERBOSITY=UVM_MEDIUM \
        ${EXTRA_ARGS} \
        -do "run -all; quit -f" \
        tb_top \
        -l "${TEST_NAME}.log"

    echo ""
    echo "--- Log: ${WORK_DIR}/${TEST_NAME}.log ---"

# =============================================================================
# Xcelium (xrun) Flow
# =============================================================================
elif [ "${TOOL}" == "xcelium" ] || [ "${TOOL}" == "xrun" ]; then

    WORK_DIR="${SIM_DIR}/xrun_work"
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"

    echo ""
    echo "--- Compiling and running with Xcelium ---"
    xrun \
        -sv \
        -uvm \
        -uvmhome CDNS-1.2 \
        +define+UVM_NO_DEPRECATED \
        -timescale 1ns/1ps \
        +incdir+"${TB_DIR}" \
        -access +rwc \
        +UVM_TESTNAME="${TEST_NAME}" \
        +UVM_VERBOSITY=UVM_MEDIUM \
        ${EXTRA_ARGS} \
        ${DUT_FILES} \
        ${TB_FILES} \
        -log "${TEST_NAME}.log"

    echo ""
    echo "--- Log: ${WORK_DIR}/${TEST_NAME}.log ---"

else
    echo "ERROR: Unknown tool '${TOOL}'. Supported: vcs | questa | xcelium"
    exit 1
fi

# =============================================================================
# Post-simulation: grep for pass/fail
# =============================================================================
echo ""
echo "--- Checking results ---"
LOG_FILE="${TEST_NAME}.log"

if [ -f "${LOG_FILE}" ]; then
    if grep -q "SIMULATION PASSED\|TEST PASSED\|UVM_ERROR :    0\|UVM_FATAL :    0" "${LOG_FILE}"; then
        echo "RESULT: PASS"
    fi
    if grep -q "SIMULATION FAILED\|TEST FAILED\|UVM_ERROR :    [^0]\|UVM_FATAL" "${LOG_FILE}"; then
        echo "RESULT: FAIL"
        echo "--- Errors/Fatals ---"
        grep -E "UVM_(ERROR|FATAL)" "${LOG_FILE}" | head -20
    fi
else
    echo "WARNING: Log file not found: ${LOG_FILE}"
fi

echo "========================================================"
echo "  Done."
echo "========================================================"
