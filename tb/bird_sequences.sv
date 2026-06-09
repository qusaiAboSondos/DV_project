// ============================================================
// bird_sequences — library of reusable test sequences
// ============================================================

// ------------------------------------------------------------
// Base sequence — common randomisation helpers
// ------------------------------------------------------------
class bird_base_seq extends uvm_sequence #(bird_packet);
    `uvm_object_utils(bird_base_seq)

    function new(string name = "bird_base_seq");
        super.new(name);
    endfunction

    // Helper: send one packet, checking randomisation
    task send_pkt(bird_packet pkt);
        start_item(pkt);
        if (!pkt.randomize())
            `uvm_fatal("bird_base_seq", "Randomisation failed")
        finish_item(pkt);
    endtask

    // Helper: send a pre-configured packet
    task send_configured(bird_packet pkt);
        start_item(pkt);
        finish_item(pkt);
    endtask
endclass : bird_base_seq

// ------------------------------------------------------------
// local_basic_seq — one valid local packet
// ------------------------------------------------------------
class local_basic_seq extends bird_base_seq;
    `uvm_object_utils(local_basic_seq)

    function new(string name = "local_basic_seq");
        super.new(name);
    endfunction

    task body();
        bird_packet pkt = bird_packet::type_id::create("pkt");
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
        bird_packet pkt;
        repeat (num_pkts) begin
            pkt = bird_packet::type_id::create("pkt");
            start_item(pkt);
            if (!pkt.randomize() with { traffic_type == 0; })
                `uvm_fatal("local_multi_seq", "Randomisation failed")
            finish_item(pkt);
        end
        `uvm_info("local_multi_seq",
            $sformatf("Sent %0d local packets", num_pkts), UVM_LOW)
    endtask
endclass : local_multi_seq

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
        bird_packet pkt;
        bit [4:0] seq = $urandom_range(1, 31);

        for (int f = 1; f <= num_frags; f++) begin
            pkt = bird_packet::type_id::create($sformatf("pkt_f%0d", f));
            start_item(pkt);
            if (!pkt.randomize() with {
                traffic_type == 1;
                seq_num      == seq;
                frag_num     == f;
                payload_len  inside {[4:32]};
            })
                `uvm_fatal("remote_inorder_seq", "Randomisation failed")
            finish_item(pkt);
        end
        `uvm_info("remote_inorder_seq",
            $sformatf("Sent %0d in-order remote frags seq=%0d", num_frags, seq), UVM_LOW)
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
        bird_packet pkt;
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
        pkt = bird_packet::type_id::create("pkt_f1");
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
            pkt = bird_packet::type_id::create(
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
        bird_packet pkt = bird_packet::type_id::create("pkt");
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
// drop_seq_num_zero_seq — should trigger drop (SEQ_NUM==0)
// ------------------------------------------------------------
class drop_seq_num_zero_seq extends bird_base_seq;
    `uvm_object_utils(drop_seq_num_zero_seq)

    function new(string name = "drop_seq_num_zero_seq");
        super.new(name);
    endfunction

    task body();
        bird_packet pkt = bird_packet::type_id::create("pkt");
        start_item(pkt);
        // Disable the valid-seq constraint so seq_num==0 can be randomised
        pkt.c_valid_seq_num.constraint_mode(0);
        if (!pkt.randomize() with {
            seq_num == 0;
        })
            `uvm_fatal("drop_seq_num_zero_seq", "Randomisation failed")
        pkt.crc16 = bird_packet::calc_crc16(pkt.payload);
        finish_item(pkt);
        `uvm_info("drop_seq_num_zero_seq", "Sent SEQ_NUM=0 packet (expect drop)", UVM_LOW)
    endtask
endclass : drop_seq_num_zero_seq

// ------------------------------------------------------------
// drop_frag_num_zero_seq — should trigger drop (FRAG_NUM==0)
// ------------------------------------------------------------
class drop_frag_num_zero_seq extends bird_base_seq;
    `uvm_object_utils(drop_frag_num_zero_seq)

    function new(string name = "drop_frag_num_zero_seq");
        super.new(name);
    endfunction

    task body();
        bird_packet pkt = bird_packet::type_id::create("pkt");
        start_item(pkt);
        if (!pkt.randomize() with { payload_len inside {[1:32]}; })
            `uvm_fatal("drop_frag_num_zero_seq", "Randomisation failed")
        pkt.frag_num = 0;
        pkt.crc16    = bird_packet::calc_crc16(pkt.payload);
        finish_item(pkt);
        `uvm_info("drop_frag_num_zero_seq", "Sent FRAG_NUM=0 packet (expect drop)", UVM_LOW)
    endtask
endclass : drop_frag_num_zero_seq

// ------------------------------------------------------------
// drop_reserved_bits_seq — nonzero reserved bits → drop
// ------------------------------------------------------------
class drop_reserved_bits_seq extends bird_base_seq;
    `uvm_object_utils(drop_reserved_bits_seq)

    function new(string name = "drop_reserved_bits_seq");
        super.new(name);
    endfunction

    task body();
        bird_packet pkt = bird_packet::type_id::create("pkt");
        start_item(pkt);
        if (!pkt.randomize() with {
            payload_len inside {[1:32]};
        })
            `uvm_fatal("drop_reserved_bits_seq", "Randomisation failed")
        // Force at least one reserved field non-zero
        pkt.rsvd_7_1 = 7'h55;
        finish_item(pkt);
        `uvm_info("drop_reserved_bits_seq",
            "Sent packet with nonzero reserved bits (expect drop)", UVM_LOW)
    endtask
endclass : drop_reserved_bits_seq

// ------------------------------------------------------------
// drop_mismatch_seq_num_seq — second frag has different SEQ_NUM
// ------------------------------------------------------------
class drop_mismatch_seq_num_seq extends bird_base_seq;
    `uvm_object_utils(drop_mismatch_seq_num_seq)

    function new(string name = "drop_mismatch_seq_num_seq");
        super.new(name);
    endfunction

    task body();
        bird_packet pkt1, pkt2;
        bit [4:0] seq1, seq2;

        seq1 = $urandom_range(1, 15);
        seq2 = $urandom_range(16, 31); // guaranteed different

        // First fragment — valid start
        pkt1 = bird_packet::type_id::create("pkt1");
        start_item(pkt1);
        if (!pkt1.randomize() with {
            traffic_type == 1;
            seq_num      == seq1;
            frag_num     == 1;
            payload_len  inside {[4:16]};
        })
            `uvm_fatal("drop_mismatch_seq_num_seq", "Randomisation failed pkt1")
        finish_item(pkt1);

        // Second fragment — mismatched SEQ_NUM → triggers drop
        pkt2 = bird_packet::type_id::create("pkt2");
        start_item(pkt2);
        if (!pkt2.randomize() with {
            traffic_type == 1;
            seq_num      == seq2;  // mismatch!
            frag_num     == 2;
            payload_len  inside {[4:16]};
        })
            `uvm_fatal("drop_mismatch_seq_num_seq", "Randomisation failed pkt2")
        finish_item(pkt2);

        `uvm_info("drop_mismatch_seq_num_seq",
            $sformatf("Sent mismatched SEQ_NUM: frag1 seq=%0d, frag2 seq=%0d (expect drop)",
                seq1, seq2), UVM_LOW)
    endtask
endclass : drop_mismatch_seq_num_seq

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
        bird_packet pkt;
        // Note: actual backpressure toggling is done in the test
        // by manipulating local_rdy/remote_rdy directly.
        // This sequence just streams packets; the driver handles stalls.
        repeat (num_pkts) begin
            pkt = bird_packet::type_id::create("pkt");
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
        bird_packet pkt;
        repeat (num_pkts) begin
            pkt = bird_packet::type_id::create("pkt");
            send_pkt(pkt);
        end
        `uvm_info("rand_test_seq",
            $sformatf("Sent %0d fully-random packets", num_pkts), UVM_LOW)
    endtask
endclass : rand_test_seq
