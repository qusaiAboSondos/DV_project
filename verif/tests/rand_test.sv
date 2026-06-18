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
        // Stall both output channels just long enough for cg_backpressure's
        // backpressure_seen bins to get sampled while output is queued, then
        // release. in_rdy is hardwired high (DUT can never backpressure the
        // input), so holding *_rdy low for the full packet stream would
        // overflow the DUT's internal output queues and lose data -- the
        // stall must only be a brief pulse, run concurrently with the
        // sequence, not held for its entire duration.
        fork
            begin
                env.agent.driver.set_local_rdy(1'b0);
                env.agent.driver.set_remote_rdy(1'b0);
                #100;
                env.agent.driver.set_local_rdy(1'b1);
                env.agent.driver.set_remote_rdy(1'b1);
            end
        join_none
        seq.start(env.agent.sequencer);
        #5000;
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
