// ============================================================================
// bird_pkg.sv - Package with all TB includes in dependency order
// ============================================================================
`ifndef BIRD_PKG_SV
`define BIRD_PKG_SV

package bird_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Sequence item
    `include "../seq/bird_transaction.sv"

    // Sequencer + base sequence (bird_base_seq.sv defines bird_sequencer class)
    `include "../seq/bird_base_seq.sv"
    `include "../seq/local_seq.sv"
    `include "../seq/remote_seq.sv"
    `include "../seq/drop_seq.sv"

    // Environment components
    `include "../env/bird_monitor.sv"
    `include "../env/bird_scoreboard.sv"
    `include "../env/bird_coverage.sv"
    `include "../env/bird_checker.sv"
    `include "../env/bird_driver.sv"
    `include "../env/bird_agent.sv"
    `include "../env/bird_env.sv"

    // Tests
    `include "../tests/bird_base_test.sv"
    `include "../tests/local_test.sv"
    `include "../tests/remote_test.sv"
    `include "../tests/drop_test.sv"
    `include "../tests/rand_test.sv"

endpackage : bird_pkg

`endif // BIRD_PKG_SV
