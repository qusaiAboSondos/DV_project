`ifndef LOCAL_TEST_SV
`define LOCAL_TEST_SV

class local_basic_test extends bird_base_test;
    `uvm_component_utils(local_basic_test)
    function new(string name = "local_basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        local_basic_seq seq = local_basic_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        #100;
        phase.drop_objection(this);
    endtask
endclass : local_basic_test

class local_multi_test extends bird_base_test;
    `uvm_component_utils(local_multi_test)
    function new(string name = "local_multi_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        local_multi_seq seq = local_multi_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        #100;
        phase.drop_objection(this);
    endtask
endclass : local_multi_test

`endif // LOCAL_TEST_SV
