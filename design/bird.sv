// ============================================================
// BIRD Behavioral SystemVerilog Model (NON-synthesizable)
// ============================================================
// Key behavioral rules:
//  - LOCAL traffic (cfg[0]==0): valid only if SEQ_NUM==1 AND FRAG_NUM==1
//  - REMOTE traffic (cfg[0]==1): SEQ_NUM and FRAG_NUM must be non-zero
//  - in_rdy is always 1 (no input backpressure)
//  - Remote output: payload packed little-endian into 32-bit words, last word = {16'h0000, crc16}
//  - drop_cnt: 16-bit wrap-around, increments once per dropped packet
// ============================================================
module bird (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        in_vld,
  output logic        in_rdy,
  input  logic [7:0]  data_in,
  input  logic [31:0] cfg,
  output logic [15:0] drop_cnt,
  output logic        local_vld,
  input  logic        local_rdy,
  output logic [7:0]  data_local,
  output logic        remote_vld,
  input  logic        remote_rdy,
  output logic [31:0] data_remote
);

  typedef byte unsigned u8_t;

  task automatic inc_drop_cnt();
    drop_cnt <= drop_cnt + 16'd1;
  endtask

  function automatic bit cfg_invalid(input logic [31:0] c);
    bit inv;
    inv = 0;
    if (c[7:1]   != 7'd0) inv = 1;
    if (c[23:21] != 3'd0) inv = 1;
    if (c[31:29] != 3'd0) inv = 1;
    if (c[15:8] == 8'd0)  inv = 1;
    if (c[0] == 1'b0) begin
      if (c[28:24] != 5'd1) inv = 1;
      if (c[20:16] != 5'd1) inv = 1;
    end else begin
      if (c[28:24] == 5'd0) inv = 1;
      if (c[20:16] == 5'd0) inv = 1;
    end
    return inv;
  endfunction

  function automatic logic [15:0] crc16_ccitt_bytes(input u8_t bytes[$]);
    logic [15:0] crc;
    crc = 16'hFFFF;
    foreach (bytes[i]) begin
      crc ^= {bytes[i], 8'h00};
      for (int b = 0; b < 8; b++) begin
        if (crc[15]) crc = (crc << 1) ^ 16'h1021;
        else         crc = (crc << 1);
      end
    end
    return crc;
  endfunction

  function automatic void pack_bytes_to_words(input u8_t bytes[$], inout logic [31:0] wq[$]);
    int i;
    i = 0;
    while (i < bytes.size()) begin
      logic [31:0] w;
      w = 32'h0;
      for (int k = 0; k < 4; k++) begin
        if (i < bytes.size()) begin
          w[8*k +: 8] = bytes[i];
          i++;
        end
      end
      wq.push_back(w);
    end
  endfunction

  always_comb in_rdy = 1'b1;

  u8_t         local_q[$];
  logic [31:0] remote_wq[$];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      local_vld   <= 1'b0;
      data_local  <= 8'h00;
      remote_vld  <= 1'b0;
      data_remote <= 32'h0;
    end else begin
      local_vld  = (local_q.size() != 0);
      data_local = (local_q.size() != 0) ? local_q[0] : 8'h00;
      if (local_vld && local_rdy) void'(local_q.pop_front());

      remote_vld  <= (remote_wq.size() != 0);
      data_remote <= (remote_wq.size() != 0) ? remote_wq[0] : 32'h0;
      if (remote_vld && remote_rdy) void'(remote_wq.pop_front());
    end
  end

  bit          remote_active;
  int unsigned active_seq;
  int unsigned active_max_frag;
  bit          frag_seen   [1:31];
  u8_t         frag_payload[1:31][$];

  task automatic clear_remote_state();
    remote_active   = 0;
    active_seq      = 0;
    active_max_frag = 0;
    for (int f = 1; f <= 31; f++) begin
      frag_seen[f] = 0;
      frag_payload[f].delete();
    end
  endtask

  task automatic drop_remote_packet_counted();
    if (remote_active) inc_drop_cnt();
    clear_remote_state();
  endtask

  function automatic bit all_frags_ready(input int unsigned n);
    bit ok;
    ok = 1;
    for (int f = 1; f <= 31; f++)
      if (f <= n && !frag_seen[f]) ok = 0;
    return ok;
  endfunction

  task automatic build_and_queue_remote_output();
    u8_t merged[$];
    logic [15:0] crc;
    merged.delete();
    for (int f = 1; f <= active_max_frag; f++) begin
      if (!frag_seen[f]) begin drop_remote_packet_counted(); return; end
      foreach (frag_payload[f][i]) merged.push_back(frag_payload[f][i]);
    end
    crc = crc16_ccitt_bytes(merged);
    pack_bytes_to_words(merged, remote_wq);
    remote_wq.push_back({16'h0000, crc});
    clear_remote_state();
  endtask

  typedef enum logic [1:0] {RX_IDLE, RX_PAYLOAD, RX_CRC} rx_state_e;
  rx_state_e   rx_st;
  bit          rx_is_remote;
  bit          rx_drop;
  int unsigned rx_seq;
  int unsigned rx_len;
  int unsigned rx_frag;
  int unsigned payload_left;
  int unsigned crc_left;
  u8_t         cur_frag_payload[$];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_st <= RX_IDLE;
      local_q.delete();
      remote_wq.delete();
      cur_frag_payload.delete();
      drop_cnt <= 16'd0;
      clear_remote_state();
    end else begin
      if (in_vld && in_rdy) begin
        unique case (rx_st)

          RX_IDLE: begin
            rx_drop      = cfg_invalid(cfg);
            rx_is_remote = cfg[0];
            rx_len       = cfg[15:8];
            rx_frag      = cfg[20:16];
            rx_seq       = cfg[28:24];
            cur_frag_payload.delete();
            payload_left = (cfg[15:8] > 0) ? (cfg[15:8] - 1) : 0;
            crc_left     = 2;

            if (rx_drop) begin
              inc_drop_cnt();
              if (cfg[0] == 1'b1 && remote_active && (cfg[28:24] == active_seq))
                drop_remote_packet_counted();
            end else begin
              if (!rx_is_remote) begin
                local_q.push_back(data_in);
              end else begin
                if (!remote_active) begin
                  if (rx_seq <= rx_frag) begin
                    remote_active = 1; active_seq = rx_seq; active_max_frag = 0;
                    for (int f = 1; f <= 31; f++) begin frag_seen[f]=0; frag_payload[f].delete(); end
                    cur_frag_payload.push_back(data_in);
                  end else inc_drop_cnt();
                end else begin
                  if (rx_seq > rx_frag) begin
                    drop_remote_packet_counted();
                    if (rx_seq == 1) begin
                      remote_active = 1; active_seq = rx_seq; active_max_frag = 0;
                      for (int f = 1; f <= 31; f++) begin frag_seen[f]=0; frag_payload[f].delete(); end
                      cur_frag_payload.push_back(data_in);
                    end else inc_drop_cnt();
                  end else cur_frag_payload.push_back(data_in);
                end
              end
            end
            rx_st <= (payload_left == 0) ? RX_CRC : RX_PAYLOAD;
          end

          RX_PAYLOAD: begin
            rx_drop = cfg_invalid(cfg);
            if ((!rx_is_remote && remote_active) || (rx_is_remote && !remote_active)) rx_drop = 1;
            if (!rx_drop) begin
              if (!rx_is_remote) local_q.push_back(data_in);
              else if (remote_active && (rx_seq <= rx_frag)) cur_frag_payload.push_back(data_in);
            end
            if (payload_left > 0) payload_left <= payload_left - 1;
            if (payload_left == 3) rx_st <= RX_CRC;
          end

          RX_CRC: begin
            if (crc_left > 0) crc_left <= crc_left - 1;
            if (!rx_drop && !rx_is_remote) local_q.push_back(data_in);
            if (crc_left == 1) begin
              if (!rx_drop && rx_is_remote) begin
                if (!(remote_active && (rx_seq <= rx_frag))) begin
                  inc_drop_cnt();
                end else begin
                  if (rx_seq < 1 || rx_seq > rx_frag) begin
                    drop_remote_packet_counted();
                  end else begin
                    frag_seen[rx_seq] = 1;
                    frag_payload[rx_seq].delete();
                    foreach (cur_frag_payload[i]) frag_payload[rx_seq].push_back(cur_frag_payload[i]);
                    if (rx_frag > active_max_frag) active_max_frag = rx_frag;
                    if (rx_seq > active_max_frag)  active_max_frag = rx_seq;
                    if (all_frags_ready(active_max_frag)) build_and_queue_remote_output();
                  end
                end
              end
              rx_st <= RX_IDLE;
            end
          end

          default: rx_st <= RX_IDLE;
        endcase
      end
    end
  end

endmodule
