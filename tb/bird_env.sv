// ============================================================================
// bird_env.sv - UVM Environment
// Contains: agent, out_monitor, scoreboard, coverage
// ============================================================================
`ifndef BIRD_ENV_SV
`define BIRD_ENV_SV

class bird_env extends uvm_env;
    `uvm_component_utils(bird_env)

    // Environment components
    bird_agent       agent;
    bird_out_monitor out_monitor;
    bird_scoreboard  scoreboard;
    bird_coverage    coverage;
    bird_checker     checker;

    function new(string name = "bird_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agent       = bird_agent::type_id::create("agent",       this);
        out_monitor = bird_out_monitor::type_id::create("out_monitor", this);
        scoreboard  = bird_scoreboard::type_id::create("scoreboard",  this);
        coverage    = bird_coverage::type_id::create("coverage",      this);
        checker     = bird_checker::type_id::create("checker",        this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect input monitor → scoreboard input imp
        agent.ap.connect(scoreboard.input_imp);

        // Connect input monitor → coverage subscriber
        agent.ap.connect(coverage.analysis_export);

        // Connect output monitor local port → scoreboard local imp
        out_monitor.local_ap.connect(scoreboard.local_imp);

        // Connect output monitor remote port → scoreboard remote imp
        out_monitor.remote_ap.connect(scoreboard.remote_imp);
    endfunction

endclass : bird_env

`endif // BIRD_ENV_SV
