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
    uvm_analysis_imp_input  #(bird_packet,      bird_scoreboard) input_imp;
    uvm_analysis_imp_local  #(bird_output_txn,  bird_scoreboard) local_imp;
    uvm_analysis_imp_remote #(bird_output_txn,  bird_scoreboard) remote_imp;

    // -------------------------------------------------------------------------
    // Internal reference model state
    // -------------------------------------------------------------------------

    // Queue of expected local transactions
    // Each entry = byte array (payload + CRC)
    byte unsigned expected_local[$][$];

    // Remote fragment accumulation: keyed by seq_num
    // Each entry: assoc array of frag_num → payload bytes
    byte unsigned remote_frags[int][int][];   // [seq_num][frag_num][bytes]
    int           remote_max_frag[int];       // max frag_num seen per seq_num

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
    endfunction

    // -------------------------------------------------------------------------
    // write_input - called by bird_in_monitor analysis port
    // Builds expected outputs using the reference model
    // -------------------------------------------------------------------------
    function void write_input(bird_packet pkt);
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
    function void model_local(bird_packet pkt);
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

    // Accumulate remote fragments and assemble when complete
    function void model_remote(bird_packet pkt);
        int sn = int'(pkt.seq_num);
        int fn = int'(pkt.frag_num);
        byte unsigned merged[];
        logic [31:0] words[$];
        int total_bytes;
        int word_idx;
        logic [15:0] new_crc;

        // Check for mismatched SEQ_NUM during ongoing accumulation
        // (handled by tracking which seq_nums are in flight)
        // Store fragment
        remote_frags[sn][fn] = new[pkt.payload.size()](pkt.payload);

        // Track max frag_num for this seq_num
        if (!remote_max_frag.exists(sn) || fn > remote_max_frag[sn])
            remote_max_frag[sn] = fn;

        // Check if we have all fragments 1..max_frag_num
        // We assume max_frag_num is the highest frag_num received
        // (simplified model: when all frags 1..N received, assemble)
        begin
            bit complete = 1;
            for (int f = 1; f <= remote_max_frag[sn]; f++) begin
                if (!remote_frags[sn].exists(f)) begin
                    complete = 0;
                    break;
                end
            end

            if (complete && remote_max_frag[sn] >= 1) begin
                // Merge payloads in fragment order
                total_bytes = 0;
                for (int f = 1; f <= remote_max_frag[sn]; f++)
                    total_bytes += remote_frags[sn][f].size();

                merged = new[total_bytes];
                word_idx = 0;
                for (int f = 1; f <= remote_max_frag[sn]; f++) begin
                    foreach (remote_frags[sn][f][b]) begin
                        merged[word_idx++] = remote_frags[sn][f][b];
                    end
                end

                // Recalculate CRC16 over merged payload
                new_crc = bird_packet::calc_crc16(merged);

                // Pack into 32-bit words (big-endian, pad last word with zeros)
                words.delete();
                begin
                    int n = merged.size();
                    int full_words = n / 4;
                    int rem = n % 4;
                    for (int w = 0; w < full_words; w++) begin
                        logic [31:0] word;
                        word = {merged[w*4], merged[w*4+1], merged[w*4+2], merged[w*4+3]};
                        words.push_back(word);
                    end
                    if (rem > 0) begin
                        logic [31:0] last_word = 32'h0;
                        for (int b = 0; b < rem; b++)
                            last_word[31 - b*8 -: 8] = merged[full_words*4 + b];
                        words.push_back(last_word);
                    end
                    // Append CRC as final 16-bit value in a 32-bit word
                    // (CRC appended as MSB-first in final word or separate)
                    words.push_back({new_crc, 16'h0});
                end

                expected_remote.push_back(words);

                `uvm_info("bird_scoreboard",
                    $sformatf("Model: assembled remote packet seq=%0d, %0d frags, %0d merged bytes",
                        sn, remote_max_frag[sn], total_bytes), UVM_MEDIUM)

                // Clean up accumulated state
                remote_frags.delete(sn);
                remote_max_frag.delete(sn);
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

        // Check drop counter
        if (observed_drop_cnt !== expected_drop_cnt) begin
            `uvm_error("bird_scoreboard",
                $sformatf("drop_cnt mismatch: observed=%0d, expected=%0d",
                    observed_drop_cnt, expected_drop_cnt))
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
        `uvm_info("bird_scoreboard", $sformatf(
            "\n====================================================\n"
            "  SCOREBOARD SUMMARY\n"
            "  Checks PASSED : %0d\n"
            "  Checks FAILED : %0d\n"
            "  Expected Drops: %0d\n"
            "  Observed Drops: %0d\n"
            "====================================================",
            checks_passed, checks_failed,
            expected_drop_cnt, observed_drop_cnt), UVM_NONE)

        if (checks_failed == 0)
            `uvm_info("bird_scoreboard", "*** TEST PASSED ***", UVM_NONE)
        else
            `uvm_error("bird_scoreboard", "*** TEST FAILED ***")
    endfunction

endclass : bird_scoreboard

`endif // BIRD_SCOREBOARD_SV
