// ============================================================
// local_seq.sv — local traffic sequences
// ============================================================

// ------------------------------------------------------------
// local_basic_seq — one valid local packet
// ------------------------------------------------------------
class local_basic_seq extends bird_base_seq;
    `uvm_object_utils(local_basic_seq)

    function new(string name = "local_basic_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt = bird_transaction::type_id::create("pkt");
        start_item(pkt);
        if (!pkt.randomize() with {
            traffic_type == 0;
            payload_len  inside {[1:64]};
        })
            `uvm_fatal("local_basic_seq", "Randomisation failed")
        finish_item(pkt);
        `uvm_info("local_basic_seq", "Sent one local packet", UVM_LOW)
    endtask
endclass : local_basic_seq

// ------------------------------------------------------------
// local_multi_seq — multiple local packets back-to-back
// ------------------------------------------------------------
class local_multi_seq extends bird_base_seq;
    `uvm_object_utils(local_multi_seq)
    int unsigned num_pkts = 8;

    function new(string name = "local_multi_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt;
        repeat (num_pkts) begin
            pkt = bird_transaction::type_id::create("pkt");
            start_item(pkt);
            if (!pkt.randomize() with { traffic_type == 0; })
                `uvm_fatal("local_multi_seq", "Randomisation failed")
            finish_item(pkt);
        end
        `uvm_info("local_multi_seq",
            $sformatf("Sent %0d local packets", num_pkts), UVM_LOW)
    endtask
endclass : local_multi_seq
