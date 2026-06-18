`ifndef COVERAGE_TEST_SV
`define COVERAGE_TEST_SV

class coverage_test extends bird_base_test;
    `uvm_component_utils(coverage_test)
    function new(string name = "coverage_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        payload_sweep_seq    s1 = payload_sweep_seq::type_id::create("s1");
        remote_single_frag_seq s2 = remote_single_frag_seq::type_id::create("s2");
        remote_maxfrag_seq   s3 = remote_maxfrag_seq::type_id::create("s3");
        phase.raise_objection(this);
        s1.start(env.agent.sequencer);
        #1000;
        s2.start(env.agent.sequencer);
        #1000;
        s3.start(env.agent.sequencer);
        #80000;
        phase.drop_objection(this);
    endtask
endclass : coverage_test

`endif // COVERAGE_TEST_SV
