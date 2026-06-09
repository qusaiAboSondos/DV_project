// ============================================================================
// bird_pkg.sv - Package that imports UVM and includes all TB files in order
// ============================================================================
`ifndef BIRD_PKG_SV
`define BIRD_PKG_SV

package bird_pkg;

    // Import UVM base library
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // -------------------------------------------------------------------------
    // Include order matters:
    //   1. Sequence item (bird_packet) - no dependencies
    //   2. Sequencer - depends on bird_packet
    //   3. Driver - depends on bird_packet, uses virtual interface
    //   4. Sequences - depends on bird_packet, sequencer
    //   5. Monitors - depends on bird_packet, output txn type
    //   6. Scoreboard - depends on bird_packet, output txn type
    //   7. Coverage - depends on bird_packet
    //   8. Agent - depends on driver, sequencer, in_monitor
    //   9. Env - depends on agent, out_monitor, scoreboard, coverage
    //  10. Tests - depends on env and all sequences
    // -------------------------------------------------------------------------

    `include "bird_packet.sv"
    `include "bird_sequencer.sv"
    `include "bird_driver.sv"
    `include "bird_sequences.sv"
    `include "bird_in_monitor.sv"
    `include "bird_out_monitor.sv"
    `include "bird_scoreboard.sv"
    `include "bird_coverage.sv"
    `include "bird_checker.sv"
    `include "bird_agent.sv"
    `include "bird_env.sv"
    `include "bird_tests.sv"

endpackage : bird_pkg

`endif // BIRD_PKG_SV
