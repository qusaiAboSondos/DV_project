// ============================================================
// bird_transaction — UVM sequence item
// Represents one BIRD fragment (one cfg word + payload bytes)
// ============================================================
class bird_transaction extends uvm_sequence_item;
    `uvm_object_utils(bird_transaction)

    // ---- cfg field breakdown --------------------------------
    rand bit         traffic_type;   // cfg[0]   0=local, 1=remote
    rand bit [7:0]   payload_len;    // cfg[15:8] 1-255
    rand bit [4:0]   frag_num;       // cfg[20:16] 1-31
    rand bit [4:0]   seq_num;        // cfg[28:24] 1-31

    // Reserved bits — kept as rand so error injection is easy
    rand bit [6:0]   rsvd_7_1;      // cfg[7:1]
    rand bit [2:0]   rsvd_23_21;    // cfg[23:21]
    rand bit [2:0]   rsvd_31_29;    // cfg[31:29]

    // ---- Payload & CRC --------------------------------------
    rand byte unsigned payload[];    // randomised payload bytes
    bit  [15:0]        crc16;        // computed after randomisation

    // ---- Valid-packet constraints ---------------------------
    constraint c_valid_traffic_type {
        soft traffic_type inside {0, 1};
    }

    constraint c_valid_payload_len {
        payload_len inside {[1:255]};
    }

    constraint c_valid_frag_num {
        frag_num inside {[1:31]};
    }

    constraint c_valid_seq_num {
        seq_num inside {[1:31]};
    }

    constraint c_rsvd_zero {
        rsvd_7_1   == 7'h0;
        rsvd_23_21 == 3'h0;
        rsvd_31_29 == 3'h0;
    }

    constraint c_payload_size {
        payload.size() == payload_len;
    }

    // Local traffic: frag_num must be 1
    constraint c_local_frag {
        (traffic_type == 0) -> frag_num == 5'h1;
    }

    // ---- post_randomize: compute CRC ------------------------
    function void post_randomize();
        crc16 = calc_crc16(payload);
    endfunction

    // ---- CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) -----
    static function bit [15:0] calc_crc16(byte unsigned data[]);
        bit [15:0] crc = 16'hFFFF;
        foreach (data[i]) begin
            crc = crc16_byte(crc, data[i]);
        end
        return crc;
    endfunction

    static function bit [15:0] crc16_byte(bit [15:0] crc, byte unsigned b);
        bit [15:0] poly = 16'h1021;
        for (int j = 7; j >= 0; j--) begin
            bit msb = crc[15];
            crc = crc << 1;
            if (((b >> j) & 1'b1) ^ msb)
                crc = crc ^ poly;
        end
        return crc;
    endfunction

    // ---- Assemble cfg word ----------------------------------
    function logic [31:0] get_cfg();
        logic [31:0] c;
        c[0]     = traffic_type;
        c[7:1]   = rsvd_7_1;
        c[15:8]  = payload_len;
        c[20:16] = frag_num;
        c[23:21] = rsvd_23_21;
        c[28:24] = seq_num;
        c[31:29] = rsvd_31_29;
        return c;
    endfunction

    // ---- UVM standard overrides -----------------------------
    function new(string name = "bird_transaction");
        super.new(name);
    endfunction

    function void do_copy(uvm_object rhs);
        bird_transaction rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("bird_transaction", "do_copy: type mismatch")
        super.do_copy(rhs);
        traffic_type = rhs_.traffic_type;
        payload_len  = rhs_.payload_len;
        frag_num     = rhs_.frag_num;
        seq_num      = rhs_.seq_num;
        rsvd_7_1     = rhs_.rsvd_7_1;
        rsvd_23_21   = rhs_.rsvd_23_21;
        rsvd_31_29   = rhs_.rsvd_31_29;
        payload      = new[rhs_.payload.size()](rhs_.payload);
        crc16        = rhs_.crc16;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        bird_transaction rhs_;
        bit eq;
        if (!$cast(rhs_, rhs)) return 0;
        eq = super.do_compare(rhs, comparer);
        eq &= (traffic_type === rhs_.traffic_type);
        eq &= (payload_len  === rhs_.payload_len);
        eq &= (frag_num     === rhs_.frag_num);
        eq &= (seq_num      === rhs_.seq_num);
        eq &= (crc16        === rhs_.crc16);
        if (payload.size() != rhs_.payload.size()) return 0;
        foreach (payload[i])
            eq &= (payload[i] === rhs_.payload[i]);
        return eq;
    endfunction

    function string convert2string();
        string s;
        s = $sformatf(
            "bird_transaction: type=%0s len=%0d frag=%0d seq=%0d crc=0x%04h rsvd[7:1]=%0h rsvd[23:21]=%0h rsvd[31:29]=%0h",
            (traffic_type ? "REMOTE" : "LOCAL"),
            payload_len, frag_num, seq_num, crc16,
            rsvd_7_1, rsvd_23_21, rsvd_31_29);
        if (payload.size() > 0) begin
            s = {s, " payload[0]="};
            s = {s, $sformatf("0x%02h", payload[0])};
            if (payload.size() > 1)
                s = {s, $sformatf("...[last]=0x%02h", payload[payload.size()-1])};
        end
        return s;
    endfunction

endclass : bird_transaction
