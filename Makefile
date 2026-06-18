VCS      := vcs
SIMV     := ./simv
URG      := urg
VCSFLAGS := -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
            +incdir+verif/tb \
            -l compile.log

# Code coverage metrics: line, condition, branch, toggle, FSM.
# Functional coverage (SV covergroups) is captured automatically
# whenever -cm is enabled; urg's "group" metric extracts it.
CMFLAGS  := -cm line+cond+branch+tgl+fsm
CMDIR    := cm.vdb

SRCS := verif/if/bird_if.sv \
        verif/cfg/bird_pkg.sv \
        verif/tb/tb_top.sv \
        design/bird.sv

.PHONY: all compile compile_cov sim_local sim_remote sim_remote_ooo sim_backpressure sim_drop sim_rand sim_coverage sim_all sim_all_cov coverage_report clean

all: compile

compile: $(SRCS)
	$(VCS) $(VCSFLAGS) $(SRCS) -o simv

compile_cov: $(SRCS)
	rm -rf $(CMDIR) simv simv.daidir csrc
	$(VCS) $(VCSFLAGS) $(CMFLAGS) -cm_dir $(CMDIR) $(SRCS) -o simv

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

sim_coverage: simv
	$(SIMV) +UVM_TESTNAME=coverage_test +UVM_VERBOSITY=UVM_LOW -l sim_coverage.log

sim_all: simv
	$(SIMV) +UVM_TESTNAME=local_basic_test    +UVM_VERBOSITY=UVM_LOW -l sim_local.log
	$(SIMV) +UVM_TESTNAME=remote_basic_test   +UVM_VERBOSITY=UVM_LOW -l sim_remote.log
	$(SIMV) +UVM_TESTNAME=remote_outoforder_test +UVM_VERBOSITY=UVM_LOW -l sim_remote_ooo.log
	$(SIMV) +UVM_TESTNAME=backpressure_test   +UVM_VERBOSITY=UVM_LOW -l sim_backpressure.log
	$(SIMV) +UVM_TESTNAME=drop_conditions_test +UVM_VERBOSITY=UVM_LOW -l sim_drop.log
	$(SIMV) +UVM_TESTNAME=rand_test           +UVM_VERBOSITY=UVM_LOW -l sim_rand.log
	$(SIMV) +UVM_TESTNAME=coverage_test       +UVM_VERBOSITY=UVM_LOW -l sim_coverage.log

# Run every test with coverage enabled, accumulating into one $(CMDIR)
sim_all_cov: compile_cov
	$(SIMV) $(CMFLAGS) -cm_name local_basic_test       -cm_dir $(CMDIR) +UVM_TESTNAME=local_basic_test       +UVM_VERBOSITY=UVM_LOW -l sim_local.log
	$(SIMV) $(CMFLAGS) -cm_name remote_basic_test       -cm_dir $(CMDIR) +UVM_TESTNAME=remote_basic_test      +UVM_VERBOSITY=UVM_LOW -l sim_remote.log
	$(SIMV) $(CMFLAGS) -cm_name remote_outoforder_test  -cm_dir $(CMDIR) +UVM_TESTNAME=remote_outoforder_test +UVM_VERBOSITY=UVM_LOW -l sim_remote_ooo.log
	$(SIMV) $(CMFLAGS) -cm_name backpressure_test       -cm_dir $(CMDIR) +UVM_TESTNAME=backpressure_test      +UVM_VERBOSITY=UVM_LOW -l sim_backpressure.log
	$(SIMV) $(CMFLAGS) -cm_name drop_conditions_test    -cm_dir $(CMDIR) +UVM_TESTNAME=drop_conditions_test   +UVM_VERBOSITY=UVM_LOW -l sim_drop.log
	$(SIMV) $(CMFLAGS) -cm_name rand_test               -cm_dir $(CMDIR) +UVM_TESTNAME=rand_test              +UVM_VERBOSITY=UVM_LOW -l sim_rand.log
	$(SIMV) $(CMFLAGS) -cm_name coverage_test           -cm_dir $(CMDIR) +UVM_TESTNAME=coverage_test          +UVM_VERBOSITY=UVM_LOW -l sim_coverage.log

# Generate code coverage (line/cond/branch/toggle/fsm) and functional
# coverage (covergroup "group" metric) reports from the merged $(CMDIR)
coverage_report:
	rm -rf report/code_coverage report/func_coverage
	mkdir -p report/code_coverage report/func_coverage
	$(URG) -dir $(CMDIR) -metric line+cond+branch+tgl+fsm -report report/code_coverage
	$(URG) -dir $(CMDIR) -metric group                    -report report/func_coverage

clean:
	rm -rf simv simv.daidir csrc *.log ucli.key *.vcd DVEfiles $(CMDIR) urgReport
