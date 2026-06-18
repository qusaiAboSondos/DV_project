`ifndef CODE_COV_TEST_SV
`define CODE_COV_TEST_SV

class drop_while_active_test extends bird_base_test;
    `uvm_component_utils(drop_while_active_test)
    function new(string name = "drop_while_active_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        remote_drop_while_active_seq    s1 = remote_drop_while_active_seq::type_id::create("s1");
        remote_payload_inactive_seq     s2 = remote_payload_inactive_seq::type_id::create("s2");
        phase.raise_objection(this);
        s1.start(env.agent.sequencer);
        s2.start(env.agent.sequencer);
        #200;
        phase.drop_objection(this);
    endtask
endclass : drop_while_active_test

`endif // CODE_COV_TEST_SV
