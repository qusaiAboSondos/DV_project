// ============================================================
// code_cov_seq.sv — stimulus targeting specific code-coverage
// holes in design/bird.sv (condition / branch / FSM-transition
// combinations not hit by the functional/drop/remote sequences).
// ============================================================

// ------------------------------------------------------------
// remote_drop_while_active_seq
// Starts a remote packet accumulation (position 1 of 3), then
// sends three more fragments designed to exercise every term
// combination of the line-298 expression in bird.sv:
//   (cfg[0]==1'b1) && remote_active && (cfg[28:24]==active_seq)
//   1) LOCAL invalid frag, position==active_seq      -> (0,1,1)
//   2) REMOTE invalid frag, position!=active_seq     -> (1,1,0)
//   3) REMOTE invalid frag, position==active_seq     -> (1,1,1)
// ------------------------------------------------------------
class remote_drop_while_active_seq extends bird_base_seq;
    `uvm_object_utils(remote_drop_while_active_seq)

    function new(string name = "remote_drop_while_active_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt;

        // Start a 3-fragment remote packet; first fragment has
        // position(seq_num)=1, so active_seq becomes 1.
        pkt = bird_transaction::type_id::create("start_frag");
        start_item(pkt);
        if (!pkt.randomize() with {
            traffic_type == 1;
            seq_num      == 1;
            frag_num     == 3;
            payload_len  inside {[4:16]};
        })
            `uvm_fatal("remote_drop_while_active_seq", "Randomisation failed")
        finish_item(pkt);

        // (0,1,1): LOCAL traffic, invalid (frag_num != 1 while seq_num==1
        // matches active_seq==1), remote stays active afterwards since the
        // cfg[0]==1 term is false -> drop_remote_packet_counted() not called.
        pkt = bird_transaction::type_id::create("local_invalid_match");
        start_item(pkt);
        pkt.c_local_frag.constraint_mode(0);
        if (!pkt.randomize() with {
            traffic_type == 0;
            seq_num      == 1;
            frag_num     == 2;   // invalid: LOCAL requires frag_num==1
            payload_len  inside {[4:16]};
        })
            `uvm_fatal("remote_drop_while_active_seq", "Randomisation failed")
        pkt.crc16 = bird_transaction::calc_crc16(pkt.payload);
        finish_item(pkt);

        // (1,1,0): REMOTE invalid (reserved bits dirty), position(2) !=
        // active_seq(1) -> remote stays active.
        pkt = bird_transaction::type_id::create("remote_invalid_nomatch");
        start_item(pkt);
        if (!pkt.randomize() with {
            traffic_type == 1;
            seq_num      == 2;
            frag_num     == 3;
            payload_len  inside {[4:16]};
        })
            `uvm_fatal("remote_drop_while_active_seq", "Randomisation failed")
        pkt.rsvd_7_1 = 7'h7f;   // force cfg_invalid()
        finish_item(pkt);

        // (1,1,1): REMOTE invalid (reserved bits dirty), position(1) ==
        // active_seq(1) -> drop_remote_packet_counted() called, clearing
        // the active remote accumulation.
        pkt = bird_transaction::type_id::create("remote_invalid_match");
        start_item(pkt);
        if (!pkt.randomize() with {
            traffic_type == 1;
            seq_num      == 1;
            frag_num     == 3;
            payload_len  inside {[4:16]};
        })
            `uvm_fatal("remote_drop_while_active_seq", "Randomisation failed")
        pkt.rsvd_23_21 = 3'h7;  // force cfg_invalid()
        finish_item(pkt);

        `uvm_info("remote_drop_while_active_seq",
            "Exercised line-298 drop-while-active condition combinations", UVM_LOW)
    endtask
endclass : remote_drop_while_active_seq

// ------------------------------------------------------------
// remote_payload_inactive_seq
// Sends a remote fragment whose first byte mismatches (position
// > total), so the FSM enters RX_PAYLOAD with remote_active==0,
// exercising the (remote_active==0, rx_seq<=rx_frag) terms of
// the line-386/422 expressions while still in payload bytes.
// ------------------------------------------------------------
class remote_payload_inactive_seq extends bird_base_seq;
    `uvm_object_utils(remote_payload_inactive_seq)

    function new(string name = "remote_payload_inactive_seq");
        super.new(name);
    endfunction

    task body();
        bird_transaction pkt;

        // position(5) > total(3): remote_active stays 0 for the whole
        // fragment (idle-state else branch just inc_drop_cnt()s), so every
        // subsequent payload byte is processed in RX_PAYLOAD with
        // remote_active==0 and rx_seq(5) > rx_frag(3) -> (0,0) term combo.
        pkt = bird_transaction::type_id::create("pkt");
        start_item(pkt);
        pkt.c_valid_seq_num.constraint_mode(0);
        pkt.c_valid_frag_num.constraint_mode(0);
        pkt.c_local_frag.constraint_mode(0);
        if (!pkt.randomize() with {
            traffic_type == 1;
            seq_num      == 5;
            frag_num     == 3;
            payload_len  inside {[8:32]};   // multi-byte payload -> RX_PAYLOAD entered
        })
            `uvm_fatal("remote_payload_inactive_seq", "Randomisation failed")
        pkt.crc16 = bird_transaction::calc_crc16(pkt.payload);
        finish_item(pkt);

        `uvm_info("remote_payload_inactive_seq",
            "Sent multi-byte remote frag with pos>total while inactive", UVM_LOW)
    endtask
endclass : remote_payload_inactive_seq
