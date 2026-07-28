/**
 * @file sim_main.cpp
 * @author Kevin Thomas
 * @brief Verilator C++ testbench for the 0x00-uart project
 * @version 1.0
 * @date 2026-08-01
 * @copyright Copyright (c) 2026
 */

#include "Vtb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>

/**
 * @brief Initialize the verilated components
 * @param argc Argument count
 * @param argv Argument vector
 * @param top Pointer to Vtb instance
 * @param tfp Pointer to VerilatedVcdC instance
 * @return void
 */
static void init_verilator(int argc, char** argv, Vtb* top, VerilatedVcdC* tfp) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    top->trace(tfp, 99);
    tfp->open("build/trace.vcd");
    top->clk = 0;
    top->resetn = 0;
}

vluint64_t main_time = 0;

/**
 * @brief Provide current simulation time for Verilator tracing
 * @return double Current time
 */
double sc_time_stamp() {
    return main_time;
}

/**
 * @brief Step the simulation by one half cycle
 * @param top Pointer to Vtb instance
 * @param tfp Pointer to VerilatedVcdC instance
 * @return void
 */
static void step_sim(Vtb* top, VerilatedVcdC* tfp) {
    if (main_time > 10) {
        top->resetn = 1;
    }
    top->clk = !top->clk;
    top->eval();
    tfp->dump(main_time);
}

/**
 * @brief Clean up verilator components
 * @param top Pointer to Vtb instance
 * @param tfp Pointer to VerilatedVcdC instance
 * @return void
 */
static void cleanup_sim(Vtb* top, VerilatedVcdC* tfp) {
    top->final();
    tfp->close();
    delete top;
    delete tfp;
}

/**
 * @brief Run the main simulation loop
 * @param top Pointer to Vtb instance
 * @param tfp Pointer to VerilatedVcdC instance
 * @return void
 */
static void run_sim_loop(Vtb* top, VerilatedVcdC* tfp) {
    while (!Verilated::gotFinish() && main_time < 100000) {
        step_sim(top, tfp);
        main_time++;
    }
}

/**
 * @brief Main execution loop
 * @param argc Argument count
 * @param argv Argument vector
 * @return int Exit status
 */
int main(int argc, char** argv) {
    Vtb* top = new Vtb;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    init_verilator(argc, argv, top, tfp);
    run_sim_loop(top, tfp);
    cleanup_sim(top, tfp);
    return 0;
}
