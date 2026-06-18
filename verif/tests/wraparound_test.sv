`ifndef WRAPAROUND_TEST_SV
`define WRAPAROUND_TEST_SV

class drop_cnt_wraparound_test extends bird_base_test;
    `uvm_component_utils(drop_cnt_wraparound_test)
    function new(string name = "drop_cnt_wraparound_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        drop_cnt_wraparound_seq s1 = drop_cnt_wraparound_seq::type_id::create("s1");
        phase.raise_objection(this);
        s1.start(env.agent.sequencer);
        #200;
        phase.drop_objection(this);
    endtask
endclass : drop_cnt_wraparound_test

`endif // WRAPAROUND_TEST_SV
