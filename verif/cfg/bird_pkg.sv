// ============================================================================
// bird_pkg.sv - Package with all TB includes in dependency order
// ============================================================================
`ifndef BIRD_PKG_SV
`define BIRD_PKG_SV

package bird_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Sequence item
    `include "verif/seq/bird_transaction.sv"

    // Sequencer + base sequence (bird_base_seq.sv defines bird_sequencer class)
    `include "verif/seq/bird_base_seq.sv"
    `include "verif/seq/local_seq.sv"
    `include "verif/seq/remote_seq.sv"
    `include "verif/seq/drop_seq.sv"
    `include "verif/seq/coverage_seq.sv"
    `include "verif/seq/code_cov_seq.sv"
    `include "verif/seq/wraparound_seq.sv"

    // Environment components
    `include "verif/env/bird_monitor.sv"
    `include "verif/env/bird_scoreboard.sv"
    `include "verif/env/bird_coverage.sv"
    `include "verif/env/bird_checker.sv"
    `include "verif/env/bird_driver.sv"
    `include "verif/env/bird_agent.sv"
    `include "verif/env/bird_env.sv"

    // Tests
    `include "verif/tests/bird_base_test.sv"
    `include "verif/tests/local_test.sv"
    `include "verif/tests/remote_test.sv"
    `include "verif/tests/drop_test.sv"
    `include "verif/tests/rand_test.sv"
    `include "verif/tests/coverage_test.sv"
    `include "verif/tests/code_cov_test.sv"
    `include "verif/tests/wraparound_test.sv"

endpackage : bird_pkg

`endif // BIRD_PKG_SV
