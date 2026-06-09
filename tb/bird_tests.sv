// ============================================================================
// bird_tests.sv - UVM Test Classes
// ============================================================================
`ifndef BIRD_TESTS_SV
`define BIRD_TESTS_SV

// ============================================================================
// bird_base_test - Base test class: builds env and sets up interface
// ============================================================================
class bird_base_test extends uvm_test;
    `uvm_component_utils(bird_base_test)

    bird_env env;

    function new(string name = "bird_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = bird_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    // Helper to run a sequence on the agent's sequencer
    task run_sequence(uvm_sequence_base seq);
        seq.start(env.agent.sequencer);
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        // Base test does nothing — subclasses override
        #100;
        phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
        uvm_report_server svr;
        super.report_phase(phase);
        svr = uvm_report_server::get_server();
        if (svr.get_severity_count(UVM_FATAL)   > 0 ||
            svr.get_severity_count(UVM_ERROR)   > 0)
            `uvm_info(get_name(), "*** SIMULATION FAILED ***", UVM_NONE)
        else
            `uvm_info(get_name(), "*** SIMULATION PASSED ***", UVM_NONE)
    endfunction

endclass : bird_base_test

// ============================================================================
// local_basic_test - Single local packet
// ============================================================================
class local_basic_test extends bird_base_test;
    `uvm_component_utils(local_basic_test)

    function new(string name = "local_basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        local_basic_seq seq;
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting local_basic_test", UVM_LOW)
        seq = local_basic_seq::type_id::create("seq");
        run_sequence(seq);
        #200;
        phase.drop_objection(this);
    endtask

endclass : local_basic_test

// ============================================================================
// remote_basic_test - Remote packet with in-order fragments
// ============================================================================
class remote_basic_test extends bird_base_test;
    `uvm_component_utils(remote_basic_test)

    function new(string name = "remote_basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        remote_inorder_seq seq;
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting remote_basic_test", UVM_LOW)
        seq = remote_inorder_seq::type_id::create("seq");
        seq.num_frags = 4;
        run_sequence(seq);
        #500;
        phase.drop_objection(this);
    endtask

endclass : remote_basic_test

// ============================================================================
// remote_outoforder_test - Remote packet with out-of-order fragments
// ============================================================================
class remote_outoforder_test extends bird_base_test;
    `uvm_component_utils(remote_outoforder_test)

    function new(string name = "remote_outoforder_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        remote_outoforder_seq seq;
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting remote_outoforder_test", UVM_LOW)
        seq = remote_outoforder_seq::type_id::create("seq");
        seq.num_frags = 6;
        run_sequence(seq);
        #1000;
        phase.drop_objection(this);
    endtask

endclass : remote_outoforder_test

// ============================================================================
// drop_conditions_test - Exercises all drop scenarios
// ============================================================================
class drop_conditions_test extends bird_base_test;
    `uvm_component_utils(drop_conditions_test)

    function new(string name = "drop_conditions_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        drop_seq_num_zero_seq    seq1;
        drop_frag_num_zero_seq   seq2;
        drop_reserved_bits_seq   seq3;
        drop_mismatch_seq_num_seq seq4;

        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting drop_conditions_test", UVM_LOW)

        seq1 = drop_seq_num_zero_seq::type_id::create("seq1");
        seq2 = drop_frag_num_zero_seq::type_id::create("seq2");
        seq3 = drop_reserved_bits_seq::type_id::create("seq3");
        seq4 = drop_mismatch_seq_num_seq::type_id::create("seq4");

        run_sequence(seq1);
        #100;
        run_sequence(seq2);
        #100;
        run_sequence(seq3);
        #100;
        run_sequence(seq4);
        #200;

        phase.drop_objection(this);
    endtask

endclass : drop_conditions_test

// ============================================================================
// backpressure_test - Tests valid/ready protocol under backpressure
// ============================================================================
class backpressure_test extends bird_base_test;
    `uvm_component_utils(backpressure_test)

    function new(string name = "backpressure_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        backpressure_seq seq;
        virtual bird_if.driver_mp vif;

        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting backpressure_test", UVM_LOW)

        // Get interface to toggle rdy signals
        if (!uvm_config_db #(virtual bird_if.driver_mp)::get(
                this, "env.agent.driver", "vif", vif))
            `uvm_warning(get_name(), "Cannot get vif for backpressure control")

        // Start sequence in background
        seq = backpressure_seq::type_id::create("seq");
        fork
            seq.start(env.agent.sequencer);
        join_none

        // Periodically toggle local_rdy to create backpressure
        if (vif != null) begin
            repeat (4) begin
                #50  vif.driver_cb.local_rdy  <= 1'b0;
                #30  vif.driver_cb.local_rdy  <= 1'b1;
                #50  vif.driver_cb.remote_rdy <= 1'b0;
                #30  vif.driver_cb.remote_rdy <= 1'b1;
            end
        end

        wait (seq.get_sequence_state() == FINISHED);
        #200;

        phase.drop_objection(this);
    endtask

endclass : backpressure_test

// ============================================================================
// rand_test - Fully randomized traffic mix
// ============================================================================
class rand_test extends bird_base_test;
    `uvm_component_utils(rand_test)

    function new(string name = "rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        rand_test_seq seq;
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting rand_test", UVM_LOW)
        seq = rand_test_seq::type_id::create("seq");
        seq.num_pkts = 50;
        run_sequence(seq);
        #1000;
        phase.drop_objection(this);
    endtask

endclass : rand_test

`endif // BIRD_TESTS_SV
