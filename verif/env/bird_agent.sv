// ============================================================================
// bird_agent.sv - UVM Agent containing driver, sequencer, and input monitor
// ============================================================================
`ifndef BIRD_AGENT_SV
`define BIRD_AGENT_SV

class bird_agent extends uvm_agent;
    `uvm_component_utils(bird_agent)

    // Agent components
    bird_driver      driver;
    bird_sequencer   sequencer;
    bird_in_monitor  in_monitor;

    // Analysis port forwarded from in_monitor
    uvm_analysis_port #(bird_transaction) ap;

    // Agent active/passive mode (UVM_ACTIVE = drive + monitor)
    // uvm_active_passive_enum is_active = UVM_ACTIVE; // inherited

    function new(string name = "bird_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ap = new("ap", this);

        // Always build the monitor
        in_monitor = bird_in_monitor::type_id::create("in_monitor", this);

        // Only build driver and sequencer in active mode
        if (get_is_active() == UVM_ACTIVE) begin
            driver     = bird_driver::type_id::create("driver",     this);
            sequencer  = bird_sequencer::type_id::create("sequencer", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect monitor analysis port to agent analysis port
        in_monitor.ap.connect(ap);

        // Connect driver to sequencer in active mode
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : bird_agent

`endif // BIRD_AGENT_SV
