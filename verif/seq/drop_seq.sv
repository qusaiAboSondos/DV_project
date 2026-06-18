// ============================================================
// drop_seq.sv — drop condition sequences
// ============================================================

// ------------------------------------------------------------
// drop_seq_num_zero_seq — should trigger drop (SEQ_NUM==0)
// ------------------------------------------------------------
class drop_seq_num_zero_seq extends bird_base_seq;
    `uvm_object_utils(drop_seq_num_zero_seq)

    function new(string name = "drop_seq_num_zero_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt = bird_transaction::type_id::create("pkt");
        start_item(pkt);
        // Disable the valid-seq constraint so seq_num==0 can be randomised
        pkt.c_valid_seq_num.constraint_mode(0);
        if (!pkt.randomize() with {
            seq_num == 0;
        })
            `uvm_fatal("drop_seq_num_zero_seq", "Randomisation failed")
        pkt.crc16 = bird_transaction::calc_crc16(pkt.payload);
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
        bird_transaction pkt = bird_transaction::type_id::create("pkt");
        start_item(pkt);
        if (!pkt.randomize() with { payload_len inside {[1:32]}; })
            `uvm_fatal("drop_frag_num_zero_seq", "Randomisation failed")
        pkt.frag_num = 0;
        pkt.crc16    = bird_transaction::calc_crc16(pkt.payload);
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
        bird_transaction pkt = bird_transaction::type_id::create("pkt");
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
// drop_reserved_bits_23_21_seq — nonzero rsvd[23:21] → drop
// ------------------------------------------------------------
class drop_reserved_bits_23_21_seq extends bird_base_seq;
    `uvm_object_utils(drop_reserved_bits_23_21_seq)

    function new(string name = "drop_reserved_bits_23_21_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt = bird_transaction::type_id::create("pkt");
        start_item(pkt);
        if (!pkt.randomize() with {
            payload_len inside {[1:32]};
        })
            `uvm_fatal("drop_reserved_bits_23_21_seq", "Randomisation failed")
        pkt.rsvd_23_21 = 3'h5;
        finish_item(pkt);
        `uvm_info("drop_reserved_bits_23_21_seq",
            "Sent packet with nonzero rsvd[23:21] (expect drop)", UVM_LOW)
    endtask
endclass : drop_reserved_bits_23_21_seq

// ------------------------------------------------------------
// drop_reserved_bits_31_29_seq — nonzero rsvd[31:29] → drop
// ------------------------------------------------------------
class drop_reserved_bits_31_29_seq extends bird_base_seq;
    `uvm_object_utils(drop_reserved_bits_31_29_seq)

    function new(string name = "drop_reserved_bits_31_29_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt = bird_transaction::type_id::create("pkt");
        start_item(pkt);
        if (!pkt.randomize() with {
            payload_len inside {[1:32]};
        })
            `uvm_fatal("drop_reserved_bits_31_29_seq", "Randomisation failed")
        pkt.rsvd_31_29 = 3'h5;
        finish_item(pkt);
        `uvm_info("drop_reserved_bits_31_29_seq",
            "Sent packet with nonzero rsvd[31:29] (expect drop)", UVM_LOW)
    endtask
endclass : drop_reserved_bits_31_29_seq

// ------------------------------------------------------------
// drop_payload_len_zero_seq — PAYLOAD_LEN==0 → drop
// Hits cg_payload_len.zero_invalid and cg_drop_conditions.cp_len_zero.yes
// ------------------------------------------------------------
class drop_payload_len_zero_seq extends bird_base_seq;
    `uvm_object_utils(drop_payload_len_zero_seq)

    function new(string name = "drop_payload_len_zero_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt = bird_transaction::type_id::create("pkt");
        start_item(pkt);
        // Disable the constraints that forbid payload_len==0 / empty payload
        pkt.c_valid_payload_len.constraint_mode(0);
        pkt.c_payload_size.constraint_mode(0);
        if (!pkt.randomize() with {
            payload_len == 0;
            payload.size() == 0;
        })
            `uvm_fatal("drop_payload_len_zero_seq", "Randomisation failed")
        pkt.crc16 = bird_transaction::calc_crc16(pkt.payload);
        finish_item(pkt);
        `uvm_info("drop_payload_len_zero_seq",
            "Sent PAYLOAD_LEN=0 packet (expect drop)", UVM_LOW)
    endtask
endclass : drop_payload_len_zero_seq

// ------------------------------------------------------------
// drop_local_seq_num_not_one_seq — LOCAL with seq_num != 1 → drop
// In the behavioral model, LOCAL traffic is valid only when
// both seq_num==1 AND frag_num==1.  Sending seq_num=2 with
// frag_num=1 must be treated as a drop condition.
// ------------------------------------------------------------
class drop_local_seq_num_not_one_seq extends bird_base_seq;
    `uvm_object_utils(drop_local_seq_num_not_one_seq)

    function new(string name = "drop_local_seq_num_not_one_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt = bird_transaction::type_id::create("pkt");
        start_item(pkt);
        // Disable the local_frag constraint so seq_num != 1 is allowed
        pkt.c_local_frag.constraint_mode(0);
        if (!pkt.randomize() with {
            traffic_type == 0;   // LOCAL traffic
            seq_num      == 2;   // seq_num != 1 → drop condition
            frag_num     == 1;   // frag_num still 1 (only seq_num violates)
            payload_len  inside {[1:32]};
        })
            `uvm_fatal("drop_local_seq_num_not_one_seq", "Randomisation failed")
        pkt.crc16 = bird_transaction::calc_crc16(pkt.payload);
        finish_item(pkt);
        `uvm_info("drop_local_seq_num_not_one_seq",
            "Sent LOCAL packet with seq_num=2, frag_num=1 (expect drop)", UVM_LOW)
    endtask
endclass : drop_local_seq_num_not_one_seq

// ------------------------------------------------------------
// drop_pos_exceeds_total_seq — seq_num > frag_num triggers drop in DUT
// (DUT drop condition: rx_seq > rx_frag i.e. position > total)
// ------------------------------------------------------------
class drop_mismatch_seq_num_seq extends bird_base_seq;
    `uvm_object_utils(drop_mismatch_seq_num_seq)

    function new(string name = "drop_mismatch_seq_num_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt;

        // Send a fragment where position(seq_num) > total(frag_num) → drop
        pkt = bird_transaction::type_id::create("pkt_drop");
        start_item(pkt);
        // Disable constraints that enforce seq_num <= frag_num
        pkt.c_valid_seq_num.constraint_mode(0);
        pkt.c_valid_frag_num.constraint_mode(0);
        pkt.c_local_frag.constraint_mode(0);
        if (!pkt.randomize() with {
            traffic_type == 1;
            seq_num      == 5;   // position = 5
            frag_num     == 3;   // total = 3 — position > total → drop
            payload_len  inside {[4:16]};
        })
            `uvm_fatal("drop_mismatch_seq_num_seq", "Randomisation failed")
        pkt.crc16 = bird_transaction::calc_crc16(pkt.payload);
        finish_item(pkt);

        `uvm_info("drop_mismatch_seq_num_seq",
            "Sent seq_num=5 frag_num=3 (pos>total → expect drop)", UVM_LOW)
    endtask
endclass : drop_mismatch_seq_num_seq
