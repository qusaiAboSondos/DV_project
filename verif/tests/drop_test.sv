`ifndef DROP_TEST_SV
`define DROP_TEST_SV

class drop_conditions_test extends bird_base_test;
    `uvm_component_utils(drop_conditions_test)
    function new(string name = "drop_conditions_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        drop_seq_num_zero_seq    s1 = drop_seq_num_zero_seq::type_id::create("s1");
        drop_frag_num_zero_seq   s2 = drop_frag_num_zero_seq::type_id::create("s2");
        drop_reserved_bits_seq   s3 = drop_reserved_bits_seq::type_id::create("s3");
        drop_mismatch_seq_num_seq s4 = drop_mismatch_seq_num_seq::type_id::create("s4");
        drop_reserved_bits_23_21_seq s5 = drop_reserved_bits_23_21_seq::type_id::create("s5");
        drop_reserved_bits_31_29_seq s6 = drop_reserved_bits_31_29_seq::type_id::create("s6");
        phase.raise_objection(this);
        s1.start(env.agent.sequencer);
        s2.start(env.agent.sequencer);
        s3.start(env.agent.sequencer);
        s4.start(env.agent.sequencer);
        s5.start(env.agent.sequencer);
        s6.start(env.agent.sequencer);
        #200;
        phase.drop_objection(this);
    endtask
endclass : drop_conditions_test

`endif // DROP_TEST_SV
