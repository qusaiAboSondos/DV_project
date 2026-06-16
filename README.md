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

### Running Simulation 

make compile

make sim_remote

make sim_remote_ooo

make sim_backpressure

make sim_rand

make sim_local
