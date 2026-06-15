// ============================================================================
// bird_scoreboard.sv - Reference model and checker
// ============================================================================
`ifndef BIRD_SCOREBOARD_SV
`define BIRD_SCOREBOARD_SV

// Declare multi-port analysis imp suffixes
`uvm_analysis_imp_decl(_input)
`uvm_analysis_imp_decl(_local)
`uvm_analysis_imp_decl(_remote)

class bird_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(bird_scoreboard)

    // Analysis imp ports
    uvm_analysis_imp_input  #(bird_transaction,      bird_scoreboard) input_imp;
    uvm_analysis_imp_local  #(bird_output_txn,  bird_scoreboard) local_imp;
    uvm_analysis_imp_remote #(bird_output_txn,  bird_scoreboard) remote_imp;

    // -------------------------------------------------------------------------
    // Internal reference model state
    // -------------------------------------------------------------------------

    // Queue of expected local transactions
    // Each entry = byte array (payload + CRC)
    byte unsigned expected_local[$][$];

    // Remote fragment accumulation:
    // DUT uses seq_num as fragment POSITION (1..N) and frag_num as TOTAL count.
    // frag_payload_by_pos[pos] holds payload bytes for that position.
    byte unsigned frag_payload_by_pos[int][];  // [position(seq_num)] -> bytes
    bit           frag_seen_pos[int];          // which positions received
    int           remote_max_frag;             // max(frag_num, seq_num) seen so far
    bit           remote_active;               // currently accumulating

    // Queue of expected remote output words
    logic [31:0]  expected_remote[$][$];

    // Drop counter tracking
    int unsigned  expected_drop_cnt;
    int unsigned  observed_drop_cnt;

    // Statistics
    int unsigned  checks_passed;
    int unsigned  checks_failed;

    // -------------------------------------------------------------------------
    function new(string name = "bird_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        input_imp  = new("input_imp",  this);
        local_imp  = new("local_imp",  this);
        remote_imp = new("remote_imp", this);
        expected_drop_cnt = 0;
        observed_drop_cnt = 0;
        checks_passed     = 0;
        checks_failed     = 0;
        remote_max_frag   = 0;
        remote_active     = 0;
    endfunction

    // -------------------------------------------------------------------------
    // write_input - called by bird_in_monitor analysis port
    // Builds expected outputs using the reference model
    // -------------------------------------------------------------------------
    function void write_input(bird_transaction pkt);
        bit drop = 0;

        `uvm_info("bird_scoreboard",
            $sformatf("Input: %s", pkt.convert2string()), UVM_HIGH)

        // ---- Drop condition checks ----

        // SEQ_NUM == 0
        if (pkt.seq_num == 0) begin
            `uvm_info("bird_scoreboard", "Drop: SEQ_NUM=0", UVM_MEDIUM)
            expected_drop_cnt++;
            drop = 1;
        end

        // FRAG_NUM == 0
        if (!drop && pkt.frag_num == 0) begin
            `uvm_info("bird_scoreboard", "Drop: FRAG_NUM=0", UVM_MEDIUM)
            expected_drop_cnt++;
            drop = 1;
        end

        // PAYLOAD_LEN outside 1-255 (0 is invalid; 255 is max for 8-bit so 0 only)
        if (!drop && pkt.payload_len == 0) begin
            `uvm_info("bird_scoreboard", "Drop: PAYLOAD_LEN=0", UVM_MEDIUM)
            expected_drop_cnt++;
            drop = 1;
        end

        // Reserved bits nonzero
        if (!drop && (pkt.rsvd_7_1 != 0 || pkt.rsvd_23_21 != 0 || pkt.rsvd_31_29 != 0)) begin
            `uvm_info("bird_scoreboard", "Drop: nonzero reserved bits", UVM_MEDIUM)
            expected_drop_cnt++;
            drop = 1;
        end

        // Local traffic: SEQ_NUM must be 1 AND FRAG_NUM must be 1, else drop
        if (!drop && pkt.traffic_type == 0 && (pkt.seq_num != 1 || pkt.frag_num != 1)) begin
            `uvm_info("bird_scoreboard", "Drop: LOCAL packet with SEQ_NUM != 1 or FRAG_NUM != 1", UVM_MEDIUM)
            expected_drop_cnt++;
            drop = 1;
        end

        if (drop) return;

        // ---- Valid packet: route to local or remote model ----
        if (pkt.traffic_type == 0) begin
            // LOCAL: forward payload + CRC directly
            model_local(pkt);
        end else begin
            // REMOTE: accumulate fragments
            model_remote(pkt);
        end
    endfunction

    // Build expected local output
    function void model_local(bird_transaction pkt);
        byte unsigned exp[];
        int idx;

        exp = new[pkt.payload.size() + 2];
        foreach (pkt.payload[i]) exp[i] = pkt.payload[i];
        exp[pkt.payload.size()]   = pkt.crc16[15:8];
        exp[pkt.payload.size()+1] = pkt.crc16[7:0];

        begin
            byte unsigned q[$];
            foreach (exp[i]) q.push_back(exp[i]);
            expected_local.push_back(q);
        end

        `uvm_info("bird_scoreboard",
            $sformatf("Model: enqueued local txn, %0d bytes", exp.size()), UVM_HIGH)
    endfunction

    // Accumulate remote fragments and assemble when complete.
    // DUT uses seq_num as fragment POSITION and frag_num as TOTAL count.
    // Drop condition: seq_num > frag_num (position exceeds total).
    function void model_remote(bird_transaction pkt);
        int pos   = int'(pkt.seq_num);   // fragment position (1..N)
        int total = int'(pkt.frag_num);  // total fragment count (N)
        byte unsigned merged[];
        logic [31:0] words[$];
        int total_bytes;
        int word_idx;
        logic [15:0] new_crc;

        // Drop if position > total (DUT condition: rx_seq > rx_frag)
        if (pos > total) begin
            `uvm_info("bird_scoreboard",
                $sformatf("Drop: seq_num(%0d) > frag_num(%0d)", pos, total), UVM_MEDIUM)
            expected_drop_cnt++;
            if (remote_active) begin
                // Flush in-flight assembly and count as drop
                expected_drop_cnt++;
                frag_payload_by_pos.delete();
                frag_seen_pos.delete();
                remote_max_frag = 0;
                remote_active   = 0;
            end
            return;
        end

        // Start assembly if not active
        if (!remote_active) remote_active = 1;

        // Store fragment payload at its position
        frag_payload_by_pos[pos] = new[pkt.payload.size()](pkt.payload);
        frag_seen_pos[pos]       = 1;

        // Update max seen: max(total, pos)
        if (total > remote_max_frag) remote_max_frag = total;
        if (pos   > remote_max_frag) remote_max_frag = pos;

        // Check completion: all positions 1..remote_max_frag received
        begin
            bit complete = 1;
            for (int f = 1; f <= remote_max_frag; f++) begin
                if (!frag_seen_pos.exists(f)) begin complete = 0; break; end
            end

            if (complete && remote_max_frag >= 1) begin
                // Merge payloads in position order (1..N)
                total_bytes = 0;
                for (int f = 1; f <= remote_max_frag; f++)
                    total_bytes += frag_payload_by_pos[f].size();

                merged    = new[total_bytes];
                word_idx  = 0;
                for (int f = 1; f <= remote_max_frag; f++)
                    foreach (frag_payload_by_pos[f][b])
                        merged[word_idx++] = frag_payload_by_pos[f][b];

                // Recompute CRC16 over merged payload
                new_crc = bird_transaction::calc_crc16(merged);

                // Pack little-endian into 32-bit words, final word = {16'h0000, crc}
                words.delete();
                begin
                    int n         = merged.size();
                    int full_wrds = n / 4;
                    int rem       = n % 4;
                    for (int w = 0; w < full_wrds; w++) begin
                        logic [31:0] word;
                        word = {merged[w*4+3], merged[w*4+2],
                                merged[w*4+1], merged[w*4]};
                        words.push_back(word);
                    end
                    if (rem > 0) begin
                        logic [31:0] last_word = 32'h0;
                        for (int b = 0; b < rem; b++)
                            last_word[8*b +: 8] = merged[full_wrds*4 + b];
                        words.push_back(last_word);
                    end
                    words.push_back({16'h0000, new_crc});
                end

                expected_remote.push_back(words);

                `uvm_info("bird_scoreboard",
                    $sformatf("Model: assembled remote packet, %0d positions, %0d merged bytes",
                        remote_max_frag, total_bytes), UVM_MEDIUM)

                // Reset assembly state
                frag_payload_by_pos.delete();
                frag_seen_pos.delete();
                remote_max_frag = 0;
                remote_active   = 0;
            end
        end
    endfunction

    // -------------------------------------------------------------------------
    // write_local - called by out_monitor local analysis port
    // -------------------------------------------------------------------------
    function void write_local(bird_output_txn txn);
        byte unsigned exp_q[$];
        bit pass = 1;

        `uvm_info("bird_scoreboard",
            $sformatf("Check local: %s", txn.convert2string()), UVM_MEDIUM)

        if (expected_local.size() == 0) begin
            `uvm_error("bird_scoreboard",
                "Unexpected local output - no expected transaction queued")
            checks_failed++;
            return;
        end

        exp_q = expected_local.pop_front();

        // Check byte count
        if (txn.local_data.size() != exp_q.size()) begin
            `uvm_error("bird_scoreboard",
                $sformatf("Local size mismatch: got %0d bytes, expected %0d",
                    txn.local_data.size(), exp_q.size()))
            pass = 0;
        end else begin
            // Check each byte
            foreach (exp_q[i]) begin
                if (txn.local_data[i] !== exp_q[i]) begin
                    `uvm_error("bird_scoreboard",
                        $sformatf("Local data[%0d] mismatch: got 0x%02h, expected 0x%02h",
                            i, txn.local_data[i], exp_q[i]))
                    pass = 0;
                end
            end
        end

        // Check drop_cnt
        observed_drop_cnt = int'(txn.drop_cnt_val);

        if (pass) begin
            `uvm_info("bird_scoreboard", "Local check PASSED", UVM_MEDIUM)
            checks_passed++;
        end else begin
            checks_failed++;
        end
    endfunction

    // -------------------------------------------------------------------------
    // write_remote - called by out_monitor remote analysis port
    // -------------------------------------------------------------------------
    function void write_remote(bird_output_txn txn);
        logic [31:0] exp_words[$];
        bit pass = 1;

        `uvm_info("bird_scoreboard",
            $sformatf("Check remote: %s", txn.convert2string()), UVM_MEDIUM)

        if (expected_remote.size() == 0) begin
            `uvm_error("bird_scoreboard",
                "Unexpected remote output - no expected transaction queued")
            checks_failed++;
            return;
        end

        exp_words = expected_remote.pop_front();

        if (txn.remote_data.size() != exp_words.size()) begin
            `uvm_error("bird_scoreboard",
                $sformatf("Remote word count mismatch: got %0d, expected %0d",
                    txn.remote_data.size(), exp_words.size()))
            pass = 0;
        end else begin
            foreach (exp_words[i]) begin
                if (txn.remote_data[i] !== exp_words[i]) begin
                    `uvm_error("bird_scoreboard",
                        $sformatf("Remote word[%0d] mismatch: got 0x%08h, expected 0x%08h",
                            i, txn.remote_data[i], exp_words[i]))
                    pass = 0;
                end
            end
        end

        observed_drop_cnt = int'(txn.drop_cnt_val);

        if (pass) begin
            `uvm_info("bird_scoreboard", "Remote check PASSED", UVM_MEDIUM)
            checks_passed++;
        end else begin
            checks_failed++;
        end
    endfunction

    // -------------------------------------------------------------------------
    // check_phase - final drop_cnt check and summary
    // -------------------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        // Check drop counter (16-bit wrapping per spec)
        if (observed_drop_cnt !== (expected_drop_cnt & 16'hFFFF)) begin
            `uvm_error("bird_scoreboard",
                $sformatf("drop_cnt mismatch: observed=%0d, expected=%0d (expected mod 65536=%0d)",
                    observed_drop_cnt, expected_drop_cnt, expected_drop_cnt & 16'hFFFF))
            checks_failed++;
        end else begin
            `uvm_info("bird_scoreboard",
                $sformatf("drop_cnt check PASSED: %0d drops", observed_drop_cnt), UVM_LOW)
        end

        // Check no leftover expected transactions
        if (expected_local.size() > 0) begin
            `uvm_error("bird_scoreboard",
                $sformatf("%0d expected local transactions never received",
                    expected_local.size()))
            checks_failed += expected_local.size();
        end

        if (expected_remote.size() > 0) begin
            `uvm_error("bird_scoreboard",
                $sformatf("%0d expected remote transactions never received",
                    expected_remote.size()))
            checks_failed += expected_remote.size();
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("bird_scoreboard", $sformatf("\n====================================================\n  SCOREBOARD SUMMARY\n  Checks PASSED : %0d\n  Checks FAILED : %0d\n  Expected Drops: %0d\n  Observed Drops: %0d\n====================================================", checks_passed, checks_failed, expected_drop_cnt, observed_drop_cnt), UVM_NONE)

        if (checks_failed == 0)
            `uvm_info("bird_scoreboard", "*** TEST PASSED ***", UVM_NONE)
        else
            `uvm_error("bird_scoreboard", "*** TEST FAILED ***")
    endfunction

endclass : bird_scoreboard

`endif // BIRD_SCOREBOARD_SV
