`ifndef BIRD_BASE_TEST_SV
`define BIRD_BASE_TEST_SV

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

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        #10;
        phase.drop_objection(this);
    endtask
endclass : bird_base_test

`endif // BIRD_BASE_TEST_SV
