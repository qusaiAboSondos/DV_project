// ============================================================================
// bird_out_monitor.sv - Monitors both local and remote output interfaces
// Collects received data and broadcasts to analysis ports
// ============================================================================
`ifndef BIRD_OUT_MONITOR_SV
`define BIRD_OUT_MONITOR_SV

// Container for observed output transactions
class bird_output_txn extends uvm_sequence_item;
    `uvm_object_utils(bird_output_txn)

    typedef enum {LOCAL_TXN, REMOTE_TXN} txn_type_e;

    txn_type_e       txn_type;
    byte unsigned    local_data[$];   // bytes observed on local output
    logic [31:0]     remote_data[$];  // 32-bit words on remote output
    logic [15:0]     drop_cnt_val;    // drop_cnt snapshot when last beat seen

    function new(string name = "bird_output_txn");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        if (txn_type == LOCAL_TXN) begin
            s = $sformatf("LOCAL_TXN: %0d bytes, drop_cnt=%0d",
                          local_data.size(), drop_cnt_val);
        end else begin
            s = $sformatf("REMOTE_TXN: %0d words, drop_cnt=%0d",
                          remote_data.size(), drop_cnt_val);
        end
        return s;
    endfunction
endclass : bird_output_txn

class bird_out_monitor extends uvm_monitor;
    `uvm_component_utils(bird_out_monitor)

    virtual bird_if.monitor_mp vif;

    // Analysis ports for local and remote outputs
    uvm_analysis_port #(bird_output_txn) local_ap;
    uvm_analysis_port #(bird_output_txn) remote_ap;

    function new(string name = "bird_out_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        local_ap  = new("local_ap",  this);
        remote_ap = new("remote_ap", this);
        if (!uvm_config_db #(virtual bird_if.monitor_mp)::get(
                this, "", "vif", vif))
            `uvm_fatal("bird_out_monitor", "Cannot get virtual interface")
    endfunction

    task run_phase(uvm_phase phase);
        // Wait for reset deassertion
        @(posedge vif.clk iff vif.rst_n === 1'b1);

        // Monitor local and remote in parallel
        fork
            monitor_local();
            monitor_remote();
        join_none
    endtask

    // Monitor local output - collect byte transactions
    task monitor_local();
        bird_output_txn txn;
        forever begin
            // Wait for local_vld=1 and local_rdy=1
            @(vif.monitor_cb);
            if (vif.monitor_cb.local_vld === 1'b1 &&
                vif.monitor_cb.local_rdy === 1'b1) begin
                txn = bird_output_txn::type_id::create("local_txn");
                txn.txn_type = bird_output_txn::LOCAL_TXN;
                txn.local_data.push_back(byte unsigned'(vif.monitor_cb.data_local));
                txn.drop_cnt_val = vif.monitor_cb.drop_cnt;

                // Continue collecting while local_vld stays high
                @(vif.monitor_cb);
                while (vif.monitor_cb.local_vld === 1'b1) begin
                    if (vif.monitor_cb.local_rdy === 1'b1)
                        txn.local_data.push_back(byte unsigned'(vif.monitor_cb.data_local));
                    @(vif.monitor_cb);
                end

                `uvm_info("bird_out_monitor",
                    $sformatf("Local: %s", txn.convert2string()), UVM_HIGH)
                local_ap.write(txn);
            end
        end
    endtask

    // Monitor remote output - collect 32-bit word transactions
    task monitor_remote();
        bird_output_txn txn;
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.remote_vld === 1'b1 &&
                vif.monitor_cb.remote_rdy === 1'b1) begin
                txn = bird_output_txn::type_id::create("remote_txn");
                txn.txn_type = bird_output_txn::REMOTE_TXN;
                txn.remote_data.push_back(vif.monitor_cb.data_remote);
                txn.drop_cnt_val = vif.monitor_cb.drop_cnt;

                @(vif.monitor_cb);
                while (vif.monitor_cb.remote_vld === 1'b1) begin
                    if (vif.monitor_cb.remote_rdy === 1'b1)
                        txn.remote_data.push_back(vif.monitor_cb.data_remote);
                    @(vif.monitor_cb);
                end

                `uvm_info("bird_out_monitor",
                    $sformatf("Remote: %s", txn.convert2string()), UVM_HIGH)
                remote_ap.write(txn);
            end
        end
    endtask

endclass : bird_out_monitor

`endif // BIRD_OUT_MONITOR_SV
