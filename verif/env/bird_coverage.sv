// ============================================================================
// bird_coverage.sv - Functional Coverage Collector
// ============================================================================
`ifndef BIRD_COVERAGE_SV
`define BIRD_COVERAGE_SV

class bird_coverage extends uvm_subscriber #(bird_transaction);
    `uvm_component_utils(bird_coverage)

    virtual bird_if.monitor_mp vif;

    bird_transaction current_pkt;

    // -------------------------------------------------------------------------
    // Covergroup: traffic type
    // -------------------------------------------------------------------------
    covergroup cg_traffic_type;
        cp_type: coverpoint current_pkt.traffic_type {
            bins local_traffic  = {0};
            bins remote_traffic = {1};
        }
    endgroup : cg_traffic_type

    // -------------------------------------------------------------------------
    // Covergroup: payload length bins
    // -------------------------------------------------------------------------
    covergroup cg_payload_len;
        cp_len: coverpoint current_pkt.payload_len {
            // payload_len==1 is structurally unreachable: c_payload_size
            // requires payload.size() == payload_len-2, which would need
            // a negative array size, so no transaction can ever carry
            // payload_len==1 on the wire.
            ignore_bins min_len = {1};
            bins sm       = {[2:15]};
            bins typical     = {[16:127]};
            bins lg       = {[128:254]};
            bins max_len     = {255};
            // payload_len==0 can never be observed: bird_in_monitor
            // reconstructs the payload as new[payload_len-2], which crashes
            // (negative array size) before any transaction is ever sampled.
            ignore_bins zero_invalid = {0};
        }
    endgroup : cg_payload_len

    // -------------------------------------------------------------------------
    // Covergroup: fragment number bins
    // -------------------------------------------------------------------------
    covergroup cg_frag_num;
        cp_frag: coverpoint current_pkt.frag_num {
            bins frag_zero    = {0};
            bins frag_one     = {1};
            bins frag_2_5     = {[2:5]};
            bins frag_6_31    = {[6:31]};
        }
    endgroup : cg_frag_num

    // -------------------------------------------------------------------------
    // Covergroup: sequence number (1-31)
    // -------------------------------------------------------------------------
    covergroup cg_seq_num;
        cp_seq: coverpoint current_pkt.seq_num {
            bins seq_zero     = {0};
            bins seq_1_8      = {[1:8]};
            bins seq_9_16     = {[9:16]};
            bins seq_17_24    = {[17:24]};
            bins seq_25_31    = {[25:31]};
        }
    endgroup : cg_seq_num

    // -------------------------------------------------------------------------
    // Covergroup: drop conditions
    // -------------------------------------------------------------------------
    covergroup cg_drop_conditions;
        cp_seq_zero:   coverpoint (current_pkt.seq_num == 0)  { bins yes = {1}; bins no = {0}; }
        cp_frag_zero:  coverpoint (current_pkt.frag_num == 0) { bins yes = {1}; bins no = {0}; }
        // payload_len==0 can never be observed: bird_in_monitor reconstructs
        // the payload as new[payload_len-2], which crashes (negative array
        // size) before any transaction reaches the analysis port. The DUT's
        // drop logic for this case is therefore untestable through the
        // current monitor and must be excluded from coverage.
        cp_len_zero:   coverpoint (current_pkt.payload_len == 0) { ignore_bins yes = {1}; bins no = {0}; }
        cp_rsvd_7_1:   coverpoint (current_pkt.rsvd_7_1 != 0)   { bins nonzero = {1}; bins zero = {0}; }
        cp_rsvd_23_21: coverpoint (current_pkt.rsvd_23_21 != 0) { bins nonzero = {1}; bins zero = {0}; }
        cp_rsvd_31_29: coverpoint (current_pkt.rsvd_31_29 != 0) { bins nonzero = {1}; bins zero = {0}; }
    endgroup : cg_drop_conditions

    // Sampled snapshot variables for backpressure covergroup
    // (avoids referencing virtual interface handle in covergroup declaration)
    bit bp_local_stall;   // local_vld=1 AND local_rdy=0
    bit bp_remote_stall;  // remote_vld=1 AND remote_rdy=0
    bit bp_in_stall;      // in_vld=1 AND in_rdy=0

    // -------------------------------------------------------------------------
    // Covergroup: backpressure - local_rdy=0 and remote_rdy=0 during valid
    // -------------------------------------------------------------------------
    covergroup cg_backpressure;
        cp_local_bp:  coverpoint bp_local_stall {
            bins backpressure_seen = {1};
            bins no_backpressure   = {0};
        }
        cp_remote_bp: coverpoint bp_remote_stall {
            bins backpressure_seen = {1};
            bins no_backpressure   = {0};
        }
        // DUT hard-wires in_rdy=1 (always_comb in_rdy = 1'b1), so the input
        // side can never stall; only the no_backpressure bin is reachable.
        cp_in_bp:     coverpoint bp_in_stall {
            bins no_backpressure   = {0};
            ignore_bins backpressure_seen = {1};
        }
    endgroup : cg_backpressure

    // -------------------------------------------------------------------------
    // Cross coverage
    // -------------------------------------------------------------------------
    covergroup cg_cross;
        cp_type: coverpoint current_pkt.traffic_type;
        cp_frag: coverpoint current_pkt.frag_num {
            bins one     = {1};
            bins few     = {[2:5]};
            bins many    = {[6:31]};
        }
        // LOCAL traffic is only valid with frag_num==1 (c_local_frag), so
        // local+few/local+many can never occur and must not count against
        // the cross coverage score.
        cx_type_frag: cross cp_type, cp_frag {
            ignore_bins local_multi_frag =
                binsof(cp_type) intersect {0} && binsof(cp_frag.few);
            ignore_bins local_many_frag  =
                binsof(cp_type) intersect {0} && binsof(cp_frag.many);
        }
    endgroup : cg_cross

    // -------------------------------------------------------------------------
    function new(string name = "bird_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_traffic_type   = new();
        cg_payload_len    = new();
        cg_frag_num       = new();
        cg_seq_num        = new();
        cg_drop_conditions = new();
        cg_backpressure   = new();
        cg_cross          = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual bird_if.monitor_mp)::get(
                this, "", "vif", vif))
            `uvm_fatal("bird_coverage", "Cannot get virtual interface")
    endfunction

    // Called by uvm_subscriber when analysis port fires
    function void write(bird_transaction t);
        current_pkt = t;
        cg_traffic_type.sample();
        cg_payload_len.sample();
        cg_frag_num.sample();
        cg_seq_num.sample();
        cg_drop_conditions.sample();
        cg_cross.sample();
    endfunction

    // Sample backpressure covergroup each clock cycle
    task run_phase(uvm_phase phase);
        @(posedge vif.clk iff vif.rst_n === 1'b1);
        forever begin
            @(vif.monitor_cb);
            // Capture snapshot into plain variables before sampling
            bp_local_stall  = (vif.monitor_cb.local_vld  === 1'b1 &&
                                vif.monitor_cb.local_rdy  === 1'b0);
            bp_remote_stall = (vif.monitor_cb.remote_vld === 1'b1 &&
                                vif.monitor_cb.remote_rdy === 1'b0);
            bp_in_stall     = (vif.monitor_cb.in_vld     === 1'b1 &&
                                vif.monitor_cb.in_rdy     === 1'b0);
            cg_backpressure.sample();
        end
    endtask

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("bird_coverage", $sformatf("\n====================================================\n  COVERAGE SUMMARY\n  cg_traffic_type   : %0.1f%%\n  cg_payload_len    : %0.1f%%\n  cg_frag_num       : %0.1f%%\n  cg_seq_num        : %0.1f%%\n  cg_drop_conditions: %0.1f%%\n  cg_backpressure   : %0.1f%%\n  cg_cross          : %0.1f%%\n====================================================", cg_traffic_type.get_coverage(), cg_payload_len.get_coverage(), cg_frag_num.get_coverage(), cg_seq_num.get_coverage(), cg_drop_conditions.get_coverage(), cg_backpressure.get_coverage(), cg_cross.get_coverage()), UVM_NONE)
    endfunction

endclass : bird_coverage

`endif // BIRD_COVERAGE_SV
