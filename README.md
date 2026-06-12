# BIRD — Birzeit Integrated Router Design
## Verification Environment | ENCS5337

### Project Structure
```
├── design/          DUT RTL implementation
├── verif/
│   ├── cfg/         Package and configuration
│   ├── env/         Environment, agent, driver, monitor, checker, coverage
│   ├── if/          SystemVerilog interface
│   ├── seq/         Transactions and sequences
│   ├── tb/          Top-level testbench
│   └── tests/       Test classes
├── report/          Coverage reports
└── test_plan.csv    Test plan (39 items)
```

### Running Simulation (VCS)
```bash
vcs -sverilog -ntb_opts uvm-1.2 \
    design/bird.sv \
    verif/if/bird_if.sv \
    verif/cfg/bird_pkg.sv \
    verif/tb/tb_top.sv \
    +incdir+verif/cfg \
    -cm line+cond+branch+tgl \
    -o simv

./simv +UVM_TESTNAME=rand_test +UVM_VERBOSITY=UVM_LOW -cm line+cond+branch+tgl
```
