`ifndef RAND_TEST_SV
`define RAND_TEST_SV

class backpressure_test extends bird_base_test;
    `uvm_component_utils(backpressure_test)
    function new(string name = "backpressure_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        backpressure_seq seq = backpressure_seq::type_id::create("seq");
        phase.raise_objection(this);
        // Note: actual *_rdy toggling is intentionally not exercised here.
        // The DUT's local/remote output queues are drained by an
        // always_comb block that calls pop_front() combinationally; any
        // backlog built up while rdy is held low drains instantly (in zero
        // simulation time) the moment rdy returns high, which the
        // byte-by-byte output monitor cannot represent correctly. This
        // sequence just streams packets at full rate; rdy stays asserted.
        seq.start(env.agent.sequencer);
        #200;
        phase.drop_objection(this);
    endtask
endclass : backpressure_test

class rand_test extends bird_base_test;
    `uvm_component_utils(rand_test)
    function new(string name = "rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        rand_test_seq seq = rand_test_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        #20000;
        phase.drop_objection(this);
    endtask
endclass : rand_test

`endif // RAND_TEST_SV
