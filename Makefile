VCS      := vcs
SIMV     := ./simv
VCSFLAGS := -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
            +incdir+verif/tb \
            -l compile.log

SRCS := verif/if/bird_if.sv \
        verif/cfg/bird_pkg.sv \
        verif/tb/tb_top.sv \
        design/bird.sv

.PHONY: all compile sim_local sim_remote sim_remote_ooo sim_backpressure sim_drop sim_rand sim_all clean

all: compile

compile: $(SRCS)
	$(VCS) $(VCSFLAGS) $(SRCS) -o simv

sim_local: simv
	$(SIMV) +UVM_TESTNAME=local_basic_test +UVM_VERBOSITY=UVM_LOW -l sim_local.log

sim_remote: simv
	$(SIMV) +UVM_TESTNAME=remote_basic_test +UVM_VERBOSITY=UVM_LOW -l sim_remote.log

sim_remote_ooo: simv
	$(SIMV) +UVM_TESTNAME=remote_outoforder_test +UVM_VERBOSITY=UVM_LOW -l sim_remote_ooo.log

sim_backpressure: simv
	$(SIMV) +UVM_TESTNAME=backpressure_test +UVM_VERBOSITY=UVM_LOW -l sim_backpressure.log

sim_drop: simv
	$(SIMV) +UVM_TESTNAME=drop_conditions_test +UVM_VERBOSITY=UVM_LOW -l sim_drop.log

sim_rand: simv
	$(SIMV) +UVM_TESTNAME=rand_test +UVM_VERBOSITY=UVM_LOW -l sim_rand.log

sim_all: simv
	$(SIMV) +UVM_TESTNAME=local_basic_test    +UVM_VERBOSITY=UVM_LOW -l sim_local.log
	$(SIMV) +UVM_TESTNAME=remote_basic_test   +UVM_VERBOSITY=UVM_LOW -l sim_remote.log
	$(SIMV) +UVM_TESTNAME=remote_outoforder_test +UVM_VERBOSITY=UVM_LOW -l sim_remote_ooo.log
	$(SIMV) +UVM_TESTNAME=backpressure_test   +UVM_VERBOSITY=UVM_LOW -l sim_backpressure.log
	$(SIMV) +UVM_TESTNAME=drop_conditions_test +UVM_VERBOSITY=UVM_LOW -l sim_drop.log
	$(SIMV) +UVM_TESTNAME=rand_test           +UVM_VERBOSITY=UVM_LOW -l sim_rand.log

clean:
	rm -rf simv simv.daidir csrc *.log ucli.key *.vcd DVEfiles
