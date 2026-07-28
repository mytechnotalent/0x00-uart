## FREE Reverse Engineering Self-Study Course [HERE](https://github.com/mytechnotalent/Reverse-Engineering-Tutorial)

## FREE UART Assembler Tutorial [HERE](TUTORIAL.md)

<br>

# 0x00-uart

A RISC-V CH32V003 embedded UART driver in pure RV32EC Assembler w/ tutorial.

<br>

## About WCH and the QingKe Core

### The company

Nanjing Qinheng Microelectronics Co., Ltd. (WCH / 南京沁恒微电子股份有限公司) was founded
in May 2004 by Wang Chunhua (王春华) in Nanjing, Jiangsu, China. The company designs
32-bit RISC-V microcontrollers and USB interface chips. Their product lines include the
CH32V (RISC-V), CH32X (RISC-V + USB), CH32L (low power), and CH58x (BLE) families. All
are open-source hardware — full reference manuals, datasheets, and SDKs are published on
GitHub (github.com/openwch).

### The name

"QingKe" (青稞) means **Tibetan highland barley** — the hardy grain that grows on the
high-altitude plateau where nothing else survives. It symbolizes resilience in harsh
conditions: a $0.30 microcontroller that works at 165 °C and costs less than its own
decoupling capacitors.

### QingKe core versions

| Core | ISA | Registers | Used in |
|------|-----|-----------|---------|
| V2A | RV32EC | 16 | **CH32V003** |
| V2C | RV32EMC | 16 | CH32V003 (multiply variant) |
| V3 | RV32IMAC | 32 | — |
| V4A | RV32IMAC | 32 | CH32V203 |
| V4B | RV32IMAC | 32 | CH32V303 |
| V4C | RV32IMAC | 32 | CH32V208 |
| V4F | RV32IMACF | 32 | CH32V307 |

### What RV32EC actually means

| Letter | Name | What it adds | Ours? |
|--------|------|-------------|-------|
| I | Integer | Base ISA, 32 registers | No |
| E | Embedded | Reduced to 16 registers | **YES** |
| M | Multiply | Hardware mul/div | No |
| A | Atomic | Atomic load/store | No |
| C | Compressed | 16-bit instruction encoding | **YES** |
| F | Float | Single-precision FPU | No |
| B | Bit manipulation | Bit twist/rotate ops | No |

**CH32V003 = RV32EC = E + C.** No multiply, no atomic, no float, no bit manipulation.

<br>

## Toolchain

| Tool | Purpose |
|------|---------|
| `riscv64-unknown-elf-as` | Assembler |
| `riscv64-unknown-elf-ld` | Linker |
| `riscv64-unknown-elf-objcopy` | Binary extraction |
| `riscv64-unknown-elf-objdump` | Disassembly / debugging |
| `riscv64-elf-gdb` | GDB for on-chip debugging |
| `wlink` | Flash via SWIO (Rust, `cargo install wlink`) |
| `wch-openocd` | On-chip debug server (WCH fork, built from source) |

ISA flags: `-march=rv32ec_zicsr -mabi=ilp32e -g`

Override the prefix if using a different toolchain:

```bash
make PREFIX=riscv-none-elf-
```

<br>

## Setup & Installation

To fully automate the installation of all necessary tools and compilers, simply run:

```bash
make setup
```

This command will automatically detect your OS (macOS, Linux, or Windows via MSYS2) and install everything required to build, debug, and simulate the RISC-V core:
- **Verilator** and **GTKWave** (with custom UDP mouseover patches)
- **RISC-V GCC Toolchain** (`riscv-none-elf-gcc`)
- **WCH OpenOCD** and **GDB** for on-chip debugging
- **wlink** for flashing via SWIO
- **Python dependencies** for Codezoom (including `windows-curses` on Windows)

### Windows Prerequisites (MSYS2)

On Windows, you must run `make setup` inside an **MSYS2** terminal, as it requires a Linux-like GNU environment to compile GTKWave from source.

To install MSYS2 and `make` in one step, open **Windows PowerShell** and run:

```powershell
winget install MSYS2.MSYS2
```

Once that finishes, open the newly installed **MSYS2 MinGW 64-bit** terminal from your Start Menu and run:
```bash
pacman -Syu
```

This updates every MSYS2 package first. Skipping it is the #1 cause of the GTKWave segfault (`cannot register existing type 'GdkPixbuf'`) on Windows, because mismatched gtk3/gdk-pixbuf versions are installed. Run it twice if the terminal asks you to close and reopen it.

Then install `make` and `gcc`:
```bash
pacman -S make gcc
```

You can then navigate to your project folder (e.g. `cd /c/Users/YourName/Desktop/0x00-uart`) and run `make setup`!

<br>


## Build

```bash
make
```

Produces `build/0x00-uart.elf` (with debug symbols) and `build/0x00-uart.bin` (raw binary for flashing).

The `-g` flag is always passed to the assembler, so the ELF retains full debug info regardless of which target you build.

<br>

## Flash

```bash
make flash
```

Uses [wlink](https://github.com/ch32-rs/wlink) to write the binary over SWIO (PD1).

<br>

## Debug — VS Code (recommended)

Press **F5** in VS Code to start a full debug session. This automatically:

1. Builds `build/0x00-uart.elf` with debug symbols
2. Starts OpenOCD as a background task (WCH-LinkE via SDI)
3. Launches `riscv64-elf-gdb`, connects to OpenOCD on `localhost:3333`
4. Resets the CPU, halts, and loads the ELF into flash

### Prerequisites

- **WCH-LinkE** programmer connected to the CH32V003 (SWIO = PD1, SWCLK = PD2)
- VS Code extension: [marus25.cortex-debug](https://marketplace.visualstudio.com/items?itemName=marus25.cortex-debug)
- VS Code extension: [zhwu95.riscv](https://marketplace.visualstudio.com/items?itemName=zhwu95.riscv)

### Debug workflow

```
F5  ──▶  make (build with -g)
         │
         ▼
         Start OpenOCD task (background)
         │
         ▼
         GDB connects to localhost:3333
         │
         ▼
         monitor reset halt
         load
         │
         ▼
         ▸ Breakpoints, stepping, registers, memory
```

### Stopping OpenOCD

When you stop the debug session (Shift+F5), OpenOCD keeps running in the VS Code terminal. Kill it manually with `Ctrl+C` in that terminal, or run:

```bash
pkill -f openocd
```

Both `make debug` and the VS Code "Start OpenOCD" task automatically kill any existing OpenOCD before starting a new one, so you don't need to do this manually when restarting.

<br>

## Debug — Terminal (manual GDB)

### Step 1 — Start OpenOCD

```bash
make debug
```

### Step 2 — Connect GDB

In a second terminal:

```bash
make gdb
```

### Useful GDB commands

| Command | Description |
|---------|-------------|
| `break main` | Set breakpoint at `main` |
| `break usart_tx` | Set breakpoint at `usart_tx` |
| `break usart_rx` | Set breakpoint at `usart_rx` |
| `continue` | Resume execution |
| `step` / `stepi` | Step one line / one instruction |
| `next` / `nexti` | Step over function / instruction |
| `print t0` | Print register `t0` |
| `x/10i $pc` | Disassemble 10 instructions from PC |
| `x/16x 0x40013800` | Dump 16 words from USART1 base |
| `monitor reset halt` | Reset and halt the CPU |
| `quit` | Exit GDB |

<br>

## OpenOCD configuration

The `openocd.cfg` configures OpenOCD for the CH32V003 with a WCH-LinkE programmer:

```
adapter driver wlinke        # WCH-LinkE USB adapter
adapter speed 6000           # 6 MHz debug clock
transport select sdi          # SDI transport (not JTAG/SWD)

wlink_set_address 0x00000000  # Flash starts at 0x00000000
set _CHIPNAME wch_riscv
sdi newtap $_CHIPNAME cpu -irlen 5 -expected-id 0x00001
```

<br>

## Simulation (Verilator + GTKWave + Codezoom)

This project includes a full cycle-accurate simulation environment using the open-source Verilator tool and a custom-patched version of GTKWave. It simulates the exact PicoRV32 processor core used in the CH32V003.

### 1. Run the simulation
```bash
make sim
```
This target:
1. Assembles your firmware (`.s` files).
2. Transpiles the `picorv32.v` and testbench to highly-optimized C++ using Verilator.
3. Executes the simulation in the background to capture all internal CPU state (registers, memory bus, etc.) and dumps it to `build/trace.vcd`.
4. Simulates UART output by intercepting memory writes to the UART registers and printing them to the terminal.

### 2. View the waveform and code execution
```bash
make wave
```
This launches a dual-window workflow:
- **GTKWave**: Opens the waveform viewer with a pre-configured save file (`sim/gtkwave_setup.gtkw`) that automatically loads the system clock, memory bus, and internal processor debug instructions. **The debug signals are formatted as ASCII text natively.**
- **Codezoom**: A terminal-based UI (`sim/codezoom.py`) that launches concurrently in a new terminal window automatically (supports macOS, Linux, and Windows).

### 3. Synchronizing Codezoom with GTKWave (Hover Feature)
Because we use a specially-patched version of GTKWave (installed via `make setup`), **hovering** your mouse over the GTKWave timeline transmits a UDP packet to Codezoom on port 6502 containing the exact Program Counter (PC) value or Assembly Instruction at that picosecond. 

To use this:
1. Move your mouse pointer directly over the green waveform trace for `dbg_insn_addr` or `dbg_ascii_instr` in GTKWave.
2. Slowly drag your mouse horizontally across the timeline.
3. A small yellow tooltip will pop up under your mouse, and Codezoom will instantly jump to the corresponding assembly instruction in your terminal window in real-time!

<br>

## Make targets

| Target | Description |
|--------|-------------|
| `make` | Build `build/0x00-uart.elf` and `build/0x00-uart.bin` |
| `make flash` | Flash `.bin` via wlink (SWIO) |
| `make debug` | Start OpenOCD debug server (port 3333) |
| `make gdb` | Connect GDB to a running OpenOCD session |
| `make clean` | Remove `build/` directory |

<br>

## Project structure

```
.
├── src/
│   ├── regs.s           # Peripheral register definitions (.equ only)
│   ├── start.s          # Reset vector table and startup code
│   ├── uart.s           # UART peripheral subroutines
│   └── main.s           # UART terminal main loop
├── datasheets/          # Official WCH reference manuals and datasheets
├── link.ld             # Linker script (16K flash, 2K RAM, 512-byte stack)
├── Makefile            # Cross-platform build (macOS / Linux / Windows)
├── openocd.cfg         # OpenOCD config for CH32V003 + WCH-LinkE
├── CH32V003xx.svd      # SVD file for cortex-debug register view
├── README.md           # This file
├── TUTORIAL.md         # UART assembly tutorial
└── .vscode/
    ├── settings.json   # *.s → riscv language mode
    ├── extensions.json # Recommended: riscv, cortex-debug
    ├── launch.json     # F5 debug config (cortex-debug + OpenOCD)
    └── tasks.json      # Start/Stop OpenOCD tasks
```

<br>

## How it works

1. **Startup**: Set stack pointer, copy .data, zero .bss, call `boot_clock_8mhz`,
   configure mstatus/mtvec, jump to `main` via `jal`.

2. **Clock**: `boot_clock_8mhz` switches SYSCLK to HSI, clears flash latency,
   sets HPRE = /3 → 8 MHz HCLK.

3. **USART init**: Enables GPIOD + USART1 + AFIO clocks, configures PD6 as AF
   output (TX) and PD1 as input pull-up (RX), sets AFIO remap for RX on PD1,
   configures BRR for 115200 baud.

4. **Echo loop**: Blocks on `usart_rx`, checks for backspace/enter, stores
   character in buffer, echoes via `usart_tx`.

5. **Dynamic remap**: `usart_tx` toggles AFIO between TX mode (Remap 10) and
   RX mode (Remap 01) on every byte. This enables half-duplex operation, as
   the CH32V003 cannot map USART1 to the badge's PD6 (TX) and PD1 (RX) pins simultaneously.

<br>

## License
This project is fully open source. Check the `LICENSE` file for more details.
