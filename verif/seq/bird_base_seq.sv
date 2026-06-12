// ============================================================
// bird_base_seq — base sequence and sequencer
// ============================================================

// ---- Sequencer ---------------------------------------------
class bird_sequencer extends uvm_sequencer #(bird_transaction);
    `uvm_component_utils(bird_sequencer)

    function new(string name = "bird_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : bird_sequencer

// ---- Base sequence — common randomisation helpers ----------
class bird_base_seq extends uvm_sequence #(bird_transaction);
    `uvm_object_utils(bird_base_seq)

    function new(string name = "bird_base_seq");
        super.new(name);
    endfunction

    // Helper: send one transaction, checking randomisation
    task send_pkt(bird_transaction pkt);
        start_item(pkt);
        if (!pkt.randomize())
            `uvm_fatal("bird_base_seq", "Randomisation failed")
        finish_item(pkt);
    endtask

    // Helper: send a pre-configured transaction
    task send_configured(bird_transaction pkt);
        start_item(pkt);
        finish_item(pkt);
    endtask
endclass : bird_base_seq
