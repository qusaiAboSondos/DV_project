// ============================================================
// coverage_seq.sv — directed sequences to close functional
// coverage gaps (payload-length bins, high fragment/seq counts)
// ============================================================

// ------------------------------------------------------------
// payload_sweep_seq — local + remote packets across payload_len
// bins {sm[2:15], typical[16:127], lg[128:254], max=255}
// ------------------------------------------------------------
class payload_sweep_seq extends bird_base_seq;
    `uvm_object_utils(payload_sweep_seq)

    function new(string name = "payload_sweep_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt;
        int unsigned lens[4] = '{14, 100, 200, 255};

        foreach (lens[i]) begin
            pkt = bird_transaction::type_id::create($sformatf("loc_pkt%0d", i));
            start_item(pkt);
            if (!pkt.randomize() with {
                traffic_type == 0;
                seq_num      == 1;
                frag_num     == 1;
                payload_len  == lens[i];
            })
                `uvm_fatal("payload_sweep_seq", "Randomisation failed")
            finish_item(pkt);

            pkt = bird_transaction::type_id::create($sformatf("rem_pkt%0d", i));
            start_item(pkt);
            if (!pkt.randomize() with {
                traffic_type == 1;
                seq_num      == 1;
                frag_num     == 1;
                payload_len  == lens[i];
            })
                `uvm_fatal("payload_sweep_seq", "Randomisation failed")
            finish_item(pkt);
            // Let the remote output queue fully drain (remote_vld must drop
            // to 0) before the next remote packet's words can be told apart
            // by the monitor, which segments transactions on remote_vld.
            #1000;
        end
        `uvm_info("payload_sweep_seq",
            "Sent payload-length sweep packets (sm/typical/lg/max bins)", UVM_LOW)
    endtask
endclass : payload_sweep_seq

// ------------------------------------------------------------
// remote_maxfrag_seq — remote packet with 31 in-order fragments
// (covers frag_6_31, seq_25_31, and cx_type_frag remote+many bins)
// ------------------------------------------------------------
class remote_maxfrag_seq extends remote_inorder_seq;
    `uvm_object_utils(remote_maxfrag_seq)

    function new(string name = "remote_maxfrag_seq");
        super.new(name);
        num_frags = 31;
    endfunction
endclass : remote_maxfrag_seq
