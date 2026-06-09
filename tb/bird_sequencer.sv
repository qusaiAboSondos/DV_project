// ============================================================
// bird_sequencer — standard UVM sequencer for bird_packet
// ============================================================
class bird_sequencer extends uvm_sequencer #(bird_packet);
    `uvm_component_utils(bird_sequencer)

    function new(string name = "bird_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : bird_sequencer
