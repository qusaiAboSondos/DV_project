// ============================================================
// BIRD — Birzeit Integrated Router Design
// Full RTL Implementation
// ============================================================
module bird (
    input  logic        clk,
    input  logic        rst_n,

    // Input interface (valid/ready handshake)
    input  logic        in_vld,
    output logic        in_rdy,
    input  logic [7:0]  data_in,
    input  logic [31:0] cfg,

    // Local output interface
    output logic        local_vld,
    input  logic        local_rdy,
    output logic [7:0]  data_local,

    // Remote output interface
    output logic        remote_vld,
    input  logic        remote_rdy,
    output logic [31:0] data_remote,

    // Status
    output logic [15:0] drop_cnt
);

// ============================================================
// Constants
// ============================================================
localparam int MAX_FRAGS   = 32; // indices 0..31, we use 1..31
localparam int MAX_PAYLOAD = 255;

// ============================================================
// Fragment storage — written only by input FSM, read by remote output FSM
// ============================================================
logic [7:0] frag_mem  [MAX_FRAGS][MAX_PAYLOAD];
logic [7:0] frag_len  [MAX_FRAGS];
logic       frag_valid[MAX_FRAGS];

// ============================================================
// cfg field decoding (combinatorial from current cfg)
// ============================================================
logic cfg_bad;
assign cfg_bad = (cfg[7:1]   != 7'd0)  ||
                 (cfg[23:21] != 3'd0)  ||
                 (cfg[31:29] != 3'd0)  ||
                 (cfg[28:24] == 5'd0)  ||   // SEQ_NUM == 0
                 (cfg[20:16] == 5'd0)  ||   // FRAG_NUM == 0
                 (cfg[15:8]  == 8'd0);      // PAYLOAD_LEN == 0

// ============================================================
// CRC16/CCITT-FALSE: poly=0x1021, init=0xFFFF, no bit reflection
// ============================================================
function automatic logic [15:0] crc16_next(
    input logic [15:0] crc,
    input logic [7:0]  data
);
    logic [15:0] c;
    integer      ii;
    c = crc;
    for (ii = 7; ii >= 0; ii = ii - 1) begin
        if ((c[15] ^ data[ii]) == 1'b1)
            c = (c << 1) ^ 16'h1021;
        else
            c = (c << 1);
    end
    return c;
endfunction

// ============================================================
// Input FSM — state encoding
// ============================================================
typedef enum logic [2:0] {
    IS_IDLE    = 3'd0,
    IS_PAYLOAD = 3'd1,
    IS_CRC0    = 3'd2,
    IS_CRC1    = 3'd3,
    IS_DROP    = 3'd4
} in_st_t;

in_st_t in_st;

// Registered cfg fields (latched on first byte of each packet)
logic        r_traffic;   // 0=local, 1=remote
logic [7:0]  r_plen;      // payload length
logic [4:0]  r_fnum;      // fragment number
logic [4:0]  r_seq;       // sequence number

// Byte counter for payload (counts bytes received starting at 1)
logic [7:0]  pay_cnt;

// For DROP state: total bytes to consume (plen+2), and how many consumed
logic [7:0]  drop_total;  // r_plen+2 for current drop (latched in IDLE)
logic [7:0]  drop_cnt_b;  // bytes consumed so far in DROP

// Remote accumulation tracking
logic [4:0]  acc_seq;
logic        acc_active;

// Trigger to start remote output FSM
logic        ro_trigger;
logic [4:0]  ro_trig_max;

// drop_cnt register
logic [15:0] drop_cnt_r;
assign drop_cnt = drop_cnt_r;

// ============================================================
// in_rdy — combinatorial
// ============================================================
always_comb begin
    case (in_st)
        IS_PAYLOAD: in_rdy = r_traffic ? 1'b1 : local_rdy;
        IS_CRC0:    in_rdy = r_traffic ? 1'b1 : local_rdy;
        IS_CRC1:    in_rdy = r_traffic ? 1'b1 : local_rdy;
        IS_DROP:    in_rdy = 1'b1;
        default:    in_rdy = 1'b1; // IS_IDLE
    endcase
end

// ============================================================
// local_vld / data_local — combinatorial passthrough
// ============================================================
always_comb begin
    if (!r_traffic &&
        (in_st == IS_PAYLOAD || in_st == IS_CRC0 || in_st == IS_CRC1)) begin
        local_vld  = in_vld;
        data_local = data_in;
    end else begin
        local_vld  = 1'b0;
        data_local = 8'h00;
    end
end

// ============================================================
// Input FSM — sequential
// ============================================================
always_ff @(posedge clk or negedge rst_n) begin : input_fsm
    // Local variables for completion check
    logic all_lower;
    logic any_higher;
    integer k;
    integer i;

    if (!rst_n) begin
        in_st       <= IS_IDLE;
        drop_cnt_r  <= 16'd0;
        pay_cnt     <= 8'd0;
        drop_total  <= 8'd0;
        drop_cnt_b  <= 8'd0;
        r_traffic   <= 1'b0;
        r_plen      <= 8'd0;
        r_fnum      <= 5'd0;
        r_seq       <= 5'd0;
        acc_seq     <= 5'd0;
        acc_active  <= 1'b0;
        ro_trigger  <= 1'b0;
        ro_trig_max <= 5'd0;
        for (i = 0; i < MAX_FRAGS; i++) begin
            frag_valid[i] <= 1'b0;
            frag_len[i]   <= 8'd0;
        end
    end else begin
        ro_trigger <= 1'b0; // default: no trigger

        // Clear frag_valid when remote output FSM completes
        if (ro_done) begin
            for (i = 0; i < MAX_FRAGS; i++)
                frag_valid[i] <= 1'b0;
        end

        case (in_st)

            // ----------------------------------------
            IS_IDLE: begin
                if (in_vld) begin
                    // Handshake occurs (in_rdy==1 always in IDLE)
                    // Latch cfg fields
                    r_traffic <= cfg[0];
                    r_plen    <= cfg[15:8];
                    r_fnum    <= cfg[20:16];
                    r_seq     <= cfg[28:24];

                    if (cfg_bad) begin
                        //--- Drop: invalid cfg ---
                        drop_cnt_r <= drop_cnt_r + 16'd1;
                        // drop_total = plen + 2, but plen could be 0
                        // We consumed 1 byte (this one), need to skip plen+2-1 more
                        // Store total for comparison
                        drop_total <= cfg[15:8] + 8'd2;
                        drop_cnt_b <= 8'd1;
                        in_st      <= IS_DROP;

                    end else if (cfg[0] == 1'b0) begin
                        //--- LOCAL traffic ---
                        if (cfg[20:16] != 5'd1) begin
                            // FRAG_NUM != 1: drop
                            drop_cnt_r <= drop_cnt_r + 16'd1;
                            drop_total <= cfg[15:8] + 8'd2;
                            drop_cnt_b <= 8'd1;
                            in_st      <= IS_DROP;
                        end else begin
                            // Valid local packet; first byte forwarded combinatorially
                            pay_cnt <= 8'd1;
                            in_st   <= (cfg[15:8] == 8'd1) ? IS_CRC0 : IS_PAYLOAD;
                        end

                    end else begin
                        //--- REMOTE traffic ---
                        if (acc_active) begin
                            if (cfg[28:24] != acc_seq) begin
                                if (cfg[20:16] == 5'd1) begin
                                    // FRAG_NUM=1 with different SEQ_NUM:
                                    // drop OLD incomplete packet, start accumulating NEW
                                    drop_cnt_r <= drop_cnt_r + 16'd1;
                                    for (i = 0; i < MAX_FRAGS; i++) begin
                                        frag_valid[i] <= 1'b0;
                                        frag_len[i]   <= 8'd0;
                                    end
                                    frag_mem[cfg[20:16]][0] <= data_in;
                                    acc_seq    <= cfg[28:24];
                                    acc_active <= 1'b1;
                                    pay_cnt    <= 8'd1;
                                    in_st      <= (cfg[15:8] == 8'd1) ? IS_CRC0 : IS_PAYLOAD;
                                end else begin
                                    // FRAG_NUM != 1 with different SEQ_NUM: drop NEW fragment
                                    drop_cnt_r <= drop_cnt_r + 16'd1;
                                    drop_total <= cfg[15:8] + 8'd2;
                                    drop_cnt_b <= 8'd1;
                                    in_st      <= IS_DROP;
                                end

                            end else if (cfg[20:16] == 5'd1) begin
                                // FRAG_NUM==1 same SEQ while accumulating: drop OLD, start fresh
                                drop_cnt_r <= drop_cnt_r + 16'd1;
                                for (i = 0; i < MAX_FRAGS; i++) begin
                                    frag_valid[i] <= 1'b0;
                                    frag_len[i]   <= 8'd0;
                                end
                                // Store first byte and begin new accumulation
                                frag_mem[cfg[20:16]][0] <= data_in;
                                acc_seq    <= cfg[28:24];
                                acc_active <= 1'b1;
                                pay_cnt    <= 8'd1;
                                in_st      <= (cfg[15:8] == 8'd1) ? IS_CRC0 : IS_PAYLOAD;

                            end else begin
                                // FRAG_NUM > 1, same SEQ
                                if (frag_valid[cfg[20:16]]) begin
                                    // Duplicate fragment: drop
                                    drop_cnt_r <= drop_cnt_r + 16'd1;
                                    drop_total <= cfg[15:8] + 8'd2;
                                    drop_cnt_b <= 8'd1;
                                    in_st      <= IS_DROP;
                                end else begin
                                    frag_mem[cfg[20:16]][0] <= data_in;
                                    pay_cnt <= 8'd1;
                                    in_st   <= (cfg[15:8] == 8'd1) ? IS_CRC0 : IS_PAYLOAD;
                                end
                            end

                        end else begin
                            // Not accumulating: start fresh (only if remote FSM is idle)
                            if (ro_busy) begin
                                // Remote FSM still outputting; drop new fragment
                                drop_cnt_r <= drop_cnt_r + 16'd1;
                                drop_total <= cfg[15:8] + 8'd2;
                                drop_cnt_b <= 8'd1;
                                in_st      <= IS_DROP;
                            end else begin
                                for (i = 0; i < MAX_FRAGS; i++) begin
                                    frag_valid[i] <= 1'b0;
                                    frag_len[i]   <= 8'd0;
                                end
                                frag_mem[cfg[20:16]][0] <= data_in;
                                acc_seq    <= cfg[28:24];
                                acc_active <= 1'b1;
                                pay_cnt    <= 8'd1;
                                in_st      <= (cfg[15:8] == 8'd1) ? IS_CRC0 : IS_PAYLOAD;
                            end
                        end
                    end
                end
            end // IS_IDLE

            // ----------------------------------------
            IS_PAYLOAD: begin
                if (in_vld & in_rdy) begin
                    if (r_traffic)
                        frag_mem[r_fnum][pay_cnt] <= data_in;
                    if (pay_cnt == r_plen - 8'd1)
                        in_st <= IS_CRC0;
                    pay_cnt <= pay_cnt + 8'd1;
                end
            end

            // ----------------------------------------
            IS_CRC0: begin
                if (in_vld & in_rdy)
                    in_st <= IS_CRC1;
            end

            // ----------------------------------------
            IS_CRC1: begin
                if (in_vld & in_rdy) begin
                    if (r_traffic) begin
                        // Mark this fragment complete (set len here to handle plen=1 case
                        // where IS_PAYLOAD is skipped entirely)
                        frag_len[r_fnum]   <= r_plen;
                        frag_valid[r_fnum] <= 1'b1;

                        // Check sequence completeness:
                        // All frags 1..r_fnum valid (r_fnum not yet written,
                        // so check 1..r_fnum-1 in current state) AND no frag > r_fnum valid.
                        all_lower  = 1'b1;
                        any_higher = 1'b0;
                        for (k = 1; k < MAX_FRAGS; k++) begin
                            if (k < r_fnum) begin
                                if (!frag_valid[k]) all_lower = 1'b0;
                            end else if (k > r_fnum) begin
                                if (frag_valid[k]) any_higher = 1'b1;
                            end
                        end

                        if (all_lower && !any_higher) begin
                            // Complete contiguous sequence 1..r_fnum
                            ro_trigger  <= 1'b1;
                            ro_trig_max <= r_fnum;
                            acc_active  <= 1'b0;
                            // frag_valid will be cleared by remote output FSM when done
                        end
                        // If sequence not complete, just keep accumulating
                    end
                    in_st <= IS_IDLE;
                end
            end

            // ----------------------------------------
            IS_DROP: begin
                // Consume remaining bytes.
                // drop_cnt_b: bytes consumed so far (1 = only the IDLE byte).
                // drop_total: total bytes in packet (plen + 2).
                // We exit when drop_cnt_b reaches drop_total (i.e., we just consumed the last byte).
                if (in_vld) begin // in_rdy==1 always here
                    if (drop_cnt_b == drop_total - 8'd1) begin
                        // Consuming the last byte this cycle
                        in_st <= IS_IDLE;
                    end else begin
                        drop_cnt_b <= drop_cnt_b + 8'd1;
                    end
                end
            end

            default: in_st <= IS_IDLE;

        endcase
    end
end // input_fsm

// ============================================================
// Remote Output FSM
// ============================================================
// Streams payload bytes of frags 1..ro_max_frag as 32-bit big-endian words,
// then appends the CRC16 of the merged payload (2 bytes big-endian),
// padding the last word with zeros if needed.

typedef enum logic [2:0] {
    RO_IDLE  = 3'd0,
    RO_DATA  = 3'd1,   // streaming payload bytes
    RO_CRCH  = 3'd2,   // emit CRC high byte
    RO_CRCL  = 3'd3,   // emit CRC low byte
    RO_FLUSH = 3'd4    // flush partial word (padded with 0)
} ro_st_t;

ro_st_t     ro_st;
logic [4:0] ro_max_frag;
logic [4:0] ro_cur_frag;
logic [7:0] ro_cur_byte;
logic [15:0] ro_crc;
logic [1:0] ro_wbyte;   // 0=MSB..3=LSB of current output word
logic [31:0] ro_wbuf;   // word accumulation buffer (zeroed for padding)
logic        ro_vld;
logic [31:0] ro_data;

assign remote_vld  = ro_vld;
assign data_remote = ro_data;

// ro_busy: remote output FSM is active; block new remote accumulation start
logic ro_busy;
assign ro_busy = (ro_st != RO_IDLE);

// ro_done: pulse from remote FSM when output is complete and frag_valid should be cleared
logic ro_done;

// Helper task-like macro for placing a byte into ro_wbuf at ro_wbyte position
// Handled inline in always_ff.

always_ff @(posedge clk or negedge rst_n) begin : remote_fsm
    // Local variables
    logic [7:0] bdata;
    logic       is_last_byte;
    logic [4:0] nxt_frag;
    logic [7:0] nxt_byte;
    logic [31:0] full_word;
    integer i;

    if (!rst_n) begin
        ro_st       <= RO_IDLE;
        ro_max_frag <= 5'd0;
        ro_cur_frag <= 5'd1;
        ro_cur_byte <= 8'd0;
        ro_crc      <= 16'hFFFF;
        ro_wbyte    <= 2'd0;
        ro_wbuf     <= 32'd0;
        ro_vld      <= 1'b0;
        ro_data     <= 32'd0;
        ro_done     <= 1'b0;
    end else begin
        ro_done <= 1'b0; // default: no done pulse

        case (ro_st)

            // ------------------------------------------
            RO_IDLE: begin
                ro_vld <= 1'b0;
                if (ro_trigger) begin
                    ro_max_frag <= ro_trig_max;
                    ro_cur_frag <= 5'd1;
                    ro_cur_byte <= 8'd0;
                    ro_crc      <= 16'hFFFF;
                    ro_wbyte    <= 2'd0;
                    ro_wbuf     <= 32'd0;
                    ro_st       <= RO_DATA;
                end
            end

            // ------------------------------------------
            // RO_DATA: consume one byte per cycle when not presenting a word.
            // When ro_wbyte reaches 3, output the completed word and stall
            // until accepted. Then continue.
            RO_DATA: begin
                if (ro_vld) begin
                    // Presenting a word: wait for handshake
                    if (remote_rdy) begin
                        ro_vld <= 1'b0;
                        // After word accepted, continue with next byte
                        // (pointers already advanced)
                        if (ro_cur_frag > ro_max_frag) begin
                            // No more payload bytes: emit CRC
                            ro_st <= RO_CRCH;
                        end
                    end
                    // else: stall
                end else begin
                    // Check if there are payload bytes remaining
                    if (ro_cur_frag <= ro_max_frag) begin
                        bdata = frag_mem[ro_cur_frag][ro_cur_byte];

                        // Update running CRC
                        ro_crc <= crc16_next(ro_crc, bdata);

                        // Advance pointers
                        is_last_byte = (ro_cur_byte == frag_len[ro_cur_frag] - 8'd1);
                        nxt_frag     = is_last_byte ? (ro_cur_frag + 5'd1) : ro_cur_frag;
                        nxt_byte     = is_last_byte ? 8'd0                 : (ro_cur_byte + 8'd1);
                        ro_cur_frag <= nxt_frag;
                        ro_cur_byte <= nxt_byte;

                        // Place byte in word buffer (big-endian)
                        case (ro_wbyte)
                            2'd0: ro_wbuf <= {bdata, 24'd0};
                            2'd1: ro_wbuf <= {ro_wbuf[31:24], bdata, 16'd0};
                            2'd2: ro_wbuf <= {ro_wbuf[31:16], bdata,  8'd0};
                            2'd3: begin
                                full_word = {ro_wbuf[31:8], bdata};
                                ro_vld    <= 1'b1;
                                ro_data   <= full_word;
                                ro_wbuf   <= 32'd0; // reset for next word
                            end
                        endcase

                        // When this is the last payload byte AND we've completed a word
                        // (ro_wbyte==3), word is output; we'll check pointers after handshake.
                        // When last payload byte but word not yet complete (ro_wbyte < 3),
                        // we go to CRCH next cycle (after advancing ro_wbyte).
                        if (is_last_byte && (nxt_frag > ro_max_frag)) begin
                            // Last payload byte
                            if (ro_wbyte == 2'd3) begin
                                // Word output this cycle; after handshake, go to CRCH
                                // We'll set ro_wbyte=0 and handle via ro_vld path above
                                ro_wbyte <= 2'd0;
                                // ro_st transition handled in ro_vld branch above
                                // BUT: we need ro_st to be RO_CRCH after this word is accepted.
                                // We can't set it now from the else (non-vld) branch since the
                                // word just became valid. Instead, set a flag or use a different
                                // approach: once nxt_frag > ro_max_frag, the ro_vld branch
                                // already checks that and goes to RO_CRCH. This works because
                                // after ro_vld deasserts next cycle, ro_cur_frag > ro_max_frag,
                                // so the ro_vld branch will set ro_st <= RO_CRCH. OK.
                            end else begin
                                // Word incomplete; after advancing wbyte, go to CRCH
                                ro_wbyte <= ro_wbyte + 2'd1;
                                ro_st    <= RO_CRCH;
                            end
                        end else begin
                            // Not last payload byte; advance wbyte
                            if (ro_wbyte == 2'd3)
                                ro_wbyte <= 2'd0;
                            else
                                ro_wbyte <= ro_wbyte + 2'd1;
                        end

                    end else begin
                        // No payload bytes left (entered RO_DATA with empty set — shouldn't happen)
                        ro_st <= RO_CRCH;
                    end
                end
            end

            // ------------------------------------------
            // RO_CRCH: CRC high byte
            RO_CRCH: begin
                if (ro_vld) begin
                    if (remote_rdy) begin
                        ro_vld  <= 1'b0;
                        ro_wbuf <= 32'd0;
                    end
                end else begin
                    // Place CRC[15:8] at ro_wbyte position
                    case (ro_wbyte)
                        2'd0: ro_wbuf <= {ro_crc[15:8], 24'd0};
                        2'd1: ro_wbuf <= {ro_wbuf[31:24], ro_crc[15:8], 16'd0};
                        2'd2: ro_wbuf <= {ro_wbuf[31:16], ro_crc[15:8],  8'd0};
                        2'd3: begin
                            ro_vld  <= 1'b1;
                            ro_data <= {ro_wbuf[31:8], ro_crc[15:8]};
                            ro_wbuf <= 32'd0;
                        end
                    endcase
                    if (ro_wbyte == 2'd3)
                        ro_wbyte <= 2'd0;
                    else
                        ro_wbyte <= ro_wbyte + 2'd1;
                    ro_st <= RO_CRCL;
                end
            end

            // ------------------------------------------
            // RO_CRCL: CRC low byte
            // When we arrive here, ro_vld may be 1 if the CRC-H byte filled a word.
            // Wait for that word to be accepted before placing CRC-L.
            RO_CRCL: begin
                if (ro_vld) begin
                    // Waiting for previously output word (CRC-H completed it) to be accepted
                    if (remote_rdy)
                        ro_vld <= 1'b0;
                    // Stay in CRCL; next cycle (ro_vld==0) we place CRC-L
                end else begin
                    // Place CRC-L byte at current ro_wbyte position
                    case (ro_wbyte)
                        2'd0: ro_wbuf <= {ro_crc[7:0], 24'd0};
                        2'd1: ro_wbuf <= {ro_wbuf[31:24], ro_crc[7:0], 16'd0};
                        2'd2: ro_wbuf <= {ro_wbuf[31:16], ro_crc[7:0],  8'd0};
                        2'd3: begin
                            ro_vld  <= 1'b1;
                            ro_data <= {ro_wbuf[31:8], ro_crc[7:0]};
                            ro_wbuf <= 32'd0;
                        end
                    endcase
                    if (ro_wbyte == 2'd3) begin
                        // Full word output now; wait for accept in RO_FLUSH
                        // (reuse FLUSH to handle the final-word handshake and cleanup)
                        ro_wbyte <= 2'd0;
                        ro_st    <= RO_FLUSH;
                    end else begin
                        // Partial word: flush it
                        ro_wbyte <= ro_wbyte + 2'd1;
                        ro_st    <= RO_FLUSH;
                    end
                end
            end

            // ------------------------------------------
            // RO_FLUSH: output partially-filled word or wait for final-word handshake
            RO_FLUSH: begin
                if (ro_vld) begin
                    if (remote_rdy) begin
                        ro_vld  <= 1'b0;
                        ro_st   <= RO_IDLE;
                        ro_done <= 1'b1; // signal input FSM to clear frag_valid
                    end
                end else begin
                    // ro_wbuf already has the partial/final word; present it
                    ro_vld  <= 1'b1;
                    ro_data <= ro_wbuf;
                end
            end

            default: ro_st <= RO_IDLE;

        endcase
    end
end // remote_fsm

endmodule : bird
