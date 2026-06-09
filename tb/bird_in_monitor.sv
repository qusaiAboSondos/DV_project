// ============================================================================
// bird_in_monitor.sv - Monitors the DUT input interface
// Collects bird_packet items and broadcasts to analysis port
// ============================================================================
`ifndef BIRD_IN_MONITOR_SV
`define BIRD_IN_MONITOR_SV

class bird_in_monitor extends uvm_monitor;
    `uvm_component_utils(bird_in_monitor)

    virtual bird_if.monitor_mp vif;

    // Analysis port - broadcasts collected packets to scoreboard/coverage
    uvm_analysis_port #(bird_packet) ap;

    function new(string name = "bird_in_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual bird_if.monitor_mp)::get(
                this, "", "vif", vif))
            `uvm_fatal("bird_in_monitor", "Cannot get virtual interface")
    endfunction

    task run_phase(uvm_phase phase);
        // Wait for reset deassertion
        @(posedge vif.clk iff vif.rst_n === 1'b1);

        forever begin
            collect_packet();
        end
    endtask

    // Collect one complete fragment transaction
    task collect_packet();
        bird_packet pkt;
        byte unsigned stream[$];
        logic [31:0] captured_cfg;
        logic [7:0]  byte_val;
        bit          first_byte;
        int          expected_len;
        int          total_bytes;  // payload + 2 CRC bytes

        first_byte = 1;
        stream.delete();

        // Wait for first valid+ready beat with in_vld asserted
        @(vif.monitor_cb);
        while (!(vif.monitor_cb.in_vld === 1'b1 && vif.monitor_cb.in_rdy === 1'b1))
            @(vif.monitor_cb);

        // Capture cfg on first beat
        captured_cfg = vif.monitor_cb.cfg;

        // Decode cfg fields
        pkt = bird_packet::type_id::create("mon_pkt");
        pkt.traffic_type = captured_cfg[0];
        pkt.rsvd_7_1     = captured_cfg[7:1];
        pkt.payload_len  = captured_cfg[15:8];
        pkt.frag_num     = captured_cfg[20:16];
        pkt.rsvd_23_21   = captured_cfg[23:21];
        pkt.seq_num      = captured_cfg[28:24];
        pkt.rsvd_31_29   = captured_cfg[31:29];

        // Total stream = payload_len + 2 (CRC bytes)
        total_bytes = int'(pkt.payload_len) + 2;

        // Collect byte stream (payload_len + 2 CRC bytes)
        // First byte already visible on this cycle
        stream.push_back(byte unsigned'(vif.monitor_cb.data_in));
        @(vif.monitor_cb);

        while (stream.size() < total_bytes) begin
            if (vif.monitor_cb.in_vld === 1'b1 && vif.monitor_cb.in_rdy === 1'b1) begin
                stream.push_back(byte unsigned'(vif.monitor_cb.data_in));
            end
            if (stream.size() < total_bytes)
                @(vif.monitor_cb);
        end

        // Extract payload and CRC from stream
        pkt.payload = new[pkt.payload_len];
        for (int i = 0; i < int'(pkt.payload_len); i++)
            pkt.payload[i] = stream[i];

        if (stream.size() >= total_bytes) begin
            pkt.crc16 = {stream[pkt.payload_len], stream[pkt.payload_len + 1]};
        end

        `uvm_info("bird_in_monitor",
            $sformatf("Collected: %s", pkt.convert2string()), UVM_HIGH)

        ap.write(pkt);
    endtask

endclass : bird_in_monitor

`endif // BIRD_IN_MONITOR_SV
