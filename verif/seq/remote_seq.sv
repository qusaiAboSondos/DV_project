// ============================================================
// remote_seq.sv — remote traffic sequences
// ============================================================

// ------------------------------------------------------------
// remote_inorder_seq — remote packet, fragments in order
// ------------------------------------------------------------
class remote_inorder_seq extends bird_base_seq;
    `uvm_object_utils(remote_inorder_seq)
    int unsigned num_frags = 4;

    function new(string name = "remote_inorder_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt;
        // seq_num = fragment index (1..num_frags), frag_num = total fragments (constant)
        for (int f = 1; f <= num_frags; f++) begin
            pkt = bird_transaction::type_id::create($sformatf("pkt_f%0d", f));
            start_item(pkt);
            if (!pkt.randomize() with {
                traffic_type == 1;
                seq_num      == f;           // fragment index
                frag_num     == num_frags;   // total fragment count
                payload_len  inside {[4:32]};
            })
                `uvm_fatal("remote_inorder_seq", "Randomisation failed")
            finish_item(pkt);
        end
        `uvm_info("remote_inorder_seq",
            $sformatf("Sent %0d in-order remote frags total=%0d", num_frags, num_frags), UVM_LOW)
    endtask
endclass : remote_inorder_seq

// ------------------------------------------------------------
// remote_outoforder_seq — remote packet, fragments out of order
// ------------------------------------------------------------
class remote_outoforder_seq extends bird_base_seq;
    `uvm_object_utils(remote_outoforder_seq)
    int unsigned num_frags = 4;

    function new(string name = "remote_outoforder_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt;
        bit [4:0] seq = $urandom_range(1, 31);
        int order[];

        // Build shuffled order of frags 2..num_frags (frag 1 must go first per spec:
        // FRAG_NUM==1 while previous incomplete is a drop condition, so frag 1
        // always initiates the assembly).
        order = new[num_frags - 1];
        foreach (order[i]) order[i] = i + 2;  // 2, 3, ..., num_frags
        // Fisher-Yates shuffle of frags 2..num_frags
        for (int i = num_frags - 2; i > 0; i--) begin
            int j = $urandom_range(0, i);
            int tmp = order[i];
            order[i] = order[j];
            order[j] = tmp;
        end

        // Always send frag 1 first to initiate assembly
        pkt = bird_transaction::type_id::create("pkt_f1");
        start_item(pkt);
        if (!pkt.randomize() with {
            traffic_type == 1;
            seq_num      == seq;
            frag_num     == 1;
            payload_len  inside {[4:32]};
        })
            `uvm_fatal("remote_outoforder_seq", "Randomisation failed for frag 1")
        finish_item(pkt);

        // Send remaining fragments in shuffled order
        foreach (order[i]) begin
            pkt = bird_transaction::type_id::create(
                $sformatf("pkt_f%0d", order[i]));
            start_item(pkt);
            if (!pkt.randomize() with {
                traffic_type == 1;
                seq_num      == seq;
                frag_num     == order[i];
                payload_len  inside {[4:32]};
            })
                `uvm_fatal("remote_outoforder_seq", "Randomisation failed")
            finish_item(pkt);
        end
        `uvm_info("remote_outoforder_seq",
            $sformatf("Sent %0d out-of-order remote frags seq=%0d (frag1 first, rest shuffled)",
                num_frags, seq), UVM_LOW)
    endtask
endclass : remote_outoforder_seq

// ------------------------------------------------------------
// remote_single_frag_seq — remote with exactly 1 fragment
// ------------------------------------------------------------
class remote_single_frag_seq extends bird_base_seq;
    `uvm_object_utils(remote_single_frag_seq)

    function new(string name = "remote_single_frag_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt = bird_transaction::type_id::create("pkt");
        start_item(pkt);
        if (!pkt.randomize() with {
            traffic_type == 1;
            frag_num     == 1;
            payload_len  inside {[1:64]};
        })
            `uvm_fatal("remote_single_frag_seq", "Randomisation failed")
        finish_item(pkt);
        `uvm_info("remote_single_frag_seq", "Sent single-frag remote packet", UVM_LOW)
    endtask
endclass : remote_single_frag_seq

// ------------------------------------------------------------
// backpressure_seq — sends packets while consumer holds rdy=0
// ------------------------------------------------------------
class backpressure_seq extends bird_base_seq;
    `uvm_object_utils(backpressure_seq)
    int unsigned num_pkts = 4;

    function new(string name = "backpressure_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt;
        // Note: actual backpressure toggling is done in the test
        // by manipulating local_rdy/remote_rdy directly.
        // This sequence just streams packets; the driver handles stalls.
        repeat (num_pkts) begin
            pkt = bird_transaction::type_id::create("pkt");
            start_item(pkt);
            if (!pkt.randomize() with { traffic_type == 0; })
                `uvm_fatal("backpressure_seq", "Randomisation failed")
            finish_item(pkt);
        end
        `uvm_info("backpressure_seq",
            $sformatf("Sent %0d packets under backpressure conditions", num_pkts), UVM_LOW)
    endtask
endclass : backpressure_seq

// ------------------------------------------------------------
// rand_test_seq — fully randomised mix
// ------------------------------------------------------------
class rand_test_seq extends bird_base_seq;
    `uvm_object_utils(rand_test_seq)
    int unsigned num_pkts = 32;

    function new(string name = "rand_test_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt;
        repeat (num_pkts) begin
            pkt = bird_transaction::type_id::create("pkt");
            send_pkt(pkt);
        end
        `uvm_info("rand_test_seq",
            $sformatf("Sent %0d fully-random packets", num_pkts), UVM_LOW)
    endtask
endclass : rand_test_seq
