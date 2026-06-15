// ============================================================
// bird_driver — drives bird_transaction items onto the DUT interface
//
// Protocol:
//   - Assert cfg stable for the entire fragment transfer
//   - Drive in_vld=1, data_in=byte, wait until in_rdy=1
//   - Stream payload bytes then CRC MSB, CRC LSB
//   - Handle backpressure: hold signals stable when in_rdy=0
// ============================================================
class bird_driver extends uvm_driver #(bird_transaction);
    `uvm_component_utils(bird_driver)

    virtual bird_if.driver_mp vif;

    function new(string name = "bird_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual bird_if.driver_mp)::get(
                this, "", "driver_mp", vif))
            `uvm_fatal("bird_driver", "Cannot get virtual interface")
    endfunction

    task run_phase(uvm_phase phase);
        bird_transaction pkt;
        // Idle state
        vif.driver_cb.in_vld    <= 1'b0;
        vif.driver_cb.data_in   <= 8'h00;
        vif.driver_cb.cfg       <= 32'h00000000;
        vif.driver_cb.local_rdy <= 1'b1;
        vif.driver_cb.remote_rdy<= 1'b1;

        // Wait for reset deassertion
        @(posedge vif.clk iff vif.rst_n === 1'b1);
        @(vif.driver_cb);

        forever begin
            seq_item_port.get_next_item(pkt);
            `uvm_info("bird_driver", {"Driving: ", pkt.convert2string()}, UVM_MEDIUM)
            drive_packet(pkt);
            seq_item_port.item_done();
        end
    endtask

    // Drive one complete fragment (payload + CRC)
    task drive_packet(bird_transaction pkt);
        logic [31:0] cfg_val;
        byte unsigned stream[];
        int stream_len;

        cfg_val = pkt.get_cfg();

        // Build byte stream: payload then CRC MSB, CRC LSB
        stream_len = pkt.payload.size() + 2;
        stream     = new[stream_len];
        foreach (pkt.payload[i])
            stream[i] = pkt.payload[i];
        stream[pkt.payload.size()]   = pkt.crc16[15:8];
        stream[pkt.payload.size()+1] = pkt.crc16[7:0];

        // Assert cfg before first byte
        vif.driver_cb.cfg <= cfg_val;
        @(vif.driver_cb);

        foreach (stream[i]) begin
            // Drive byte with in_vld=1
            vif.driver_cb.in_vld  <= 1'b1;
            vif.driver_cb.data_in <= stream[i];
            @(vif.driver_cb);
            // Wait until DUT accepts (in_rdy=1)
            while (vif.driver_cb.in_rdy !== 1'b1) begin
                @(vif.driver_cb);
            end
        end

        // De-assert valid after last byte accepted
        vif.driver_cb.in_vld  <= 1'b0;
        vif.driver_cb.data_in <= 8'h00;
        @(vif.driver_cb);
    endtask

    // Allow test to control local_rdy / remote_rdy
    task set_local_rdy(logic val);
        vif.driver_cb.local_rdy <= val;
    endtask

    task set_remote_rdy(logic val);
        vif.driver_cb.remote_rdy <= val;
    endtask

endclass : bird_driver
