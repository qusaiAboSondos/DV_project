`ifndef REMOTE_TEST_SV
`define REMOTE_TEST_SV

class remote_basic_test extends bird_base_test;
    `uvm_component_utils(remote_basic_test)
    function new(string name = "remote_basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        remote_inorder_seq seq = remote_inorder_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        #5000;
        phase.drop_objection(this);
    endtask
endclass : remote_basic_test

class remote_outoforder_test extends bird_base_test;
    `uvm_component_utils(remote_outoforder_test)
    function new(string name = "remote_outoforder_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        remote_outoforder_seq seq = remote_outoforder_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        #5000;
        phase.drop_objection(this);
    endtask
endclass : remote_outoforder_test

`endif // REMOTE_TEST_SV
