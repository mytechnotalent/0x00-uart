# 0x00-uart Tutorial — Bare-Metal UART on CH32V003

A complete, line-by-line walkthrough of every instruction in the UART terminal
firmware. No SDK, no HAL, no C — just raw assembly talking to hardware registers.

---

## Table of Contents

1. [Part 1: What is RISC-V?](#part-1-what-is-risc-v)
2. [Part 2: The CH32V003 — A $0.30 RISC-V Computer](#part-2-the-ch32v003)
3. [Part 3: The Build System](#part-3-the-build-system)
4. [Part 4: The Vector Table and Startup](#part-4-the-vector-table-and-startup)
5. [Part 5: Clock Configuration — 8 MHz from 24 MHz](#part-5-clock-configuration)
6. [Part 6: GPIO and Peripheral Clocks](#part-6-gpio-and-peripheral-clocks)
7. [Part 7: USART1 — The UART Peripheral](#part-7-usart1-the-uart-peripheral)
8. [Part 8: The Echo Loop and Terminal Logic](#part-8-the-echo-loop)
9. [Part 9: Transmit, Receive, and Print](#part-9-transmit-receive-and-print)
10. [Part 10: Dynamic AFIO Remap](#part-10-dynamic-afio-remap)
11. [Part 11: Building, Flashing, and Debugging](#part-11-building-flashing-and-debugging)

---

## Part 1: What is RISC-V?

RISC-V is an open-source instruction set architecture (ISA). Anyone can build a
RISC-V processor — no license fees, no royalties. The CH32V003 uses the QingKe
V2A core, which implements **RV32EC**:

- **R** = RISC (Reduced Instruction Set Computer)
- **V** = Vector extensions (but we don't use them)
- **32** = 32-bit registers
- **E** = Embedded (16 registers instead of 32)
- **C** = Compressed (16-bit instruction encoding)

No multiply (M), no atomic (A), no float (F), no bit manipulation (B). Just
16 registers and compressed instructions. That's it.

---

## Part 2: The CH32V003

The CH32V003 is a 32-bit RISC-V microcontroller made by WCH (Nanjing Qinheng).
It costs $0.30, has 16 KB flash, 2 KB RAM, and runs up to 48 MHz. It uses
the QingKe V2A core — WCH's own RISC-V design.

### Memory map

| Region | Start | End | Size |
|--------|-------|-----|------|
| Flash | 0x00000000 | 0x00003FFF | 16 KB |
| SRAM | 0x20000000 | 0x200007FF | 2 KB |

### Peripherals used in this firmware

| Peripheral | Base Address | Purpose |
|-----------|--------------|---------|
| RCC | 0x40021000 | Clock control |
| AFIO | 0x40010000 | Pin remapping |
| GPIOD | 0x40011400 | GPIO port D (PD1, PD6) |
| USART1 | 0x40013800 | Serial communication |

---

## Part 3: The Build System

### Makefile

```bash
make              # Build build/0x00-uart.elf and .bin
make flash        # Flash via wlink
make debug        # Start OpenOCD (port 3333)
make gdb          # Connect GDB to OpenOCD
```

ISA flags: `-march=rv32ec_zicsr -mabi=ilp32e -g`

The `-g` flag is critical — it tells the assembler to include debug symbols
(file names, line numbers, variable names) in the ELF. Without it, GDB can't
show you source code.

### Linker script

`link.ld` places:
- `.init` (vector table) at flash address 0x00000000
- `.text` (code + rodata) right after
- `.data` in RAM, copied from flash at boot
- `.bss` in RAM, zeroed at boot
- `.stack` at the top of RAM (512 bytes)

---

## Part 4: The Vector Table and Startup

### Lines 27–68: The vector table (in `src/start.s`)

```asm
.global _start
.align 2
.option norvc
.section .init

_start:
  j       handle_reset
```

At power-on, the CPU reads address 0x00000000 and jumps there. Our first
instruction is `j handle_reset` — an unconditional jump past the vector table.

The vector table follows: 38 words (4 bytes each) of interrupt handler
addresses. Each `.word` is a pointer to a function. If an interrupt fires,
the CPU jumps to the address at that interrupt's position in the table.

All our handlers point to `j 1b` — an infinite loop. We don't use
interrupts in this firmware.

### Lines 82–122: The startup routine (in `src/start.s`)

```asm
handle_reset:
.option push
.option norelax
  la      gp, __global_pointer$
.option pop
  la      sp, _eusrstack
```

**`la gp, __global_pointer$`** — Load the global pointer. GP is used for
efficient access to global variables. The `.option norelax` tells the
assembler not to replace `la` with `auipc` (which would be shorter but
less flexible).

**`la sp, _eusrstack`** — Set the stack pointer to the top of RAM
(0x20000600). The stack grows downward.

```asm
  la      a0, _data_lma
  la      a1, _data_vma
  la      a2, _edata
  bgeu    a1, a2, 2f
1:
  lw      t0, 0(a0)
  sw      t0, 0(a1)
  addi    a0, a0, 4
  addi    a1, a1, 4
  bltu    a1, a2, 1b
2:
```

This copies `.data` from flash (LMA) to RAM (VMA). If there are no
initialized variables, the loop is skipped.

```asm
  la      a0, _sbss
  la      a1, _ebss
  bgeu    a0, a1, 2f
1:
  sw      zero, 0(a0)
  addi    a0, a0, 4
  bltu    a0, a1, 1b
2:
```

This zeros the `.bss` section (uninitialized globals). It loops from `_sbss`
to `_ebss`, writing 0 to each 4-byte word.

```asm
  li      t0, 0x1880
  csrw    mstatus, t0
  li      t0, 0x3
  csrw    0x804, t0
  la      t0, _start
  ori     t0, t0, 3
  csrw    mtvec, t0
  jal     boot_clock_8mhz
  jal     main
1:
  j       1b
```

**`li t0, 0x1880; csrw mstatus, t0`** — Set MSTATUS to 0x1880 (MPP=11 for
Machine mode, MPIE=1 to save interrupt state).

**`li t0, 0x3; csrw 0x804, t0`** — Write 0x3 to CSR 0x804 (interrupt
enable — not used but required by the core).

**`la t0, _start; ori t0, t0, 3; csrw mtvec, t0`** — Set the trap vector
to `_start | 3` (vectored mode).

**`jal boot_clock_8mhz`** — Call the clock setup function to switch to 8 MHz.

**`jal main`** — Jump to the application entry point. If `main` ever
returns, the infinite loop `j 1b` catches it.

---

## Part 5: Clock Configuration

### Lines 134–155: boot_clock_8mhz (in `src/start.s`)

This function replicates the WCH C library's `SystemInit` + `SetSysClockTo_8MHz_HSI`.

```asm
boot_clock_8mhz:
  li      t0, RCC_BASE           # 0x40021000
  lw      t1, RCC_CFGR0(t0)      # Read clock configuration
  andi    t1, t1, -4             # Clear SW[1:0] — select HSI
  sw      t1, RCC_CFGR0(t0)      # Write back
```

**HSI** is the 24 MHz internal RC oscillator. It's enabled by default after
reset, but we ensure it's selected as the system clock.

```asm
1:
  lw      t1, RCC_CFGR0(t0)      # Read clock status
  andi    t1, t1, RCC_SWS        # Mask SWS bits
  bnez    t1, 1b                 # Wait until HSI selected
```

Wait for the switch to complete (10–120 µs per the datasheet).

```asm
  li      t2, FLASH_BASE
  lw      t1, FLASH_ACTLR(t2)    # Read flash access control
  andi    t1, t1, -4             # Clear LATENCY[2:0] → 0 wait states
  sw      t1, FLASH_ACTLR(t2)    # Write back
```

Set flash latency to 0 wait states (safe at 8 MHz).

```asm
  lw      t1, RCC_CFGR0(t0)      # Read clock configuration
  li      a0, 0xFFFFFF0F         # ~RCC_HPRE mask
  and     t1, t1, a0             # Clear HPRE bits [7:4]
  ori     t1, t1, RCC_HPRE_DIV3  # Set HPRE = DIV3
  sw      t1, RCC_CFGR0(t0)      # Write back
```

**Result:** SYSCLK = 24 MHz (HSI), HPRE = /3, HCLK = 8 MHz.

---

## Part 6: GPIO and Peripheral Clocks

### Lines 36–74: usart_init (in `src/uart.s`)

```asm
usart_init:
  # 1. Enable clocks for GPIOD, USART1, AFIO
  li      t1, RCC_BASE
  lw      a4, 0x18(t1)           # RCC_APB2PCENR
  li      t2, 0x4021             # USART1EN(bit 14) | IOPDEN(bit 5) | AFIOEN(bit 0)
  or      a4, a4, t2
  sw      a4, 0x18(t1)
```

**RCC_APB2PCENR** at 0x40021018 controls which APB2 peripherals have their
clocks enabled. Without the clock, a peripheral is frozen — reads return 0,
writes have no effect.

We enable three clocks simultaneously:
- **AFIOEN (bit 0)** — needed for pin remapping
- **IOPDEN (bit 5)** — needed for GPIOD (PD1, PD6)
- **USART1EN (bit 14)** — needed for USART1

```asm
  # 2. Configure GPIOD pins
  li      t1, GPIOD_BASE
  lw      a4, 0(t1)              # GPIOD_CFGLR
  li      t2, ~(0xF << 24)       # Clear PD6 config
  and     a4, a4, t2
  li      t2, (0xA << 24)        # PD6: AF Output Push-Pull 50 MHz
  or      a4, a4, t2
```

**GPIOD_CFGLR** at 0x40011400 configures pins 0–7. Each pin uses 4 bits:
CNF[1:0] + MODE[1:0].

For PD6 (TX): MODE=10 (2 MHz output), CNF=10 (AF push-pull) → 0b1010 = 0xA.

```asm
  li      t2, ~(0xF << 4)        # Clear PD1 config
  and     a4, a4, t2
  li      t2, (0x8 << 4)         # PD1: Input Pull-up
  or      a4, a4, t2
  sw      a4, 0(t1)
```

For PD1 (RX): MODE=00 (input), CNF=10 (pull-up/pull-down) → 0b1000 = 0x8.

```asm
  li      a4, (1 << 6)
  sw      a4, 0x10(t1)           # GPIOD_BSHR: set PD6 high (idle)

  lw      a4, 0x0C(t1)           # GPIOD_OUTDR
  ori     a4, a4, (1 << 1)       # PD1 pull-up
  sw      a4, 0x0C(t1)
```

Set PD6 high (UART idle state is high). Enable PD1 pull-up resistor.

```asm
  # 3. configure AFIO remap for RX on PD1 (Remap 01)
  li      t1, AFIO_BASE
  lw      a4, 4(t1)              # AFIO_PCFR1
  li      t2, ~(1 << 21)         # clear HIGH_BIT_REMAP
  and     a4, a4, t2
  ori     a4, a4, (1 << 2)       # set USART1_REMAP
  sw      a4, 4(t1)
```

Configure the AFIO alternate function register to map USART1 RX to PD1 (Remap 01).

---

## Part 7: USART1 — The UART Peripheral

### The USART1 register map

| Register | Offset | Address | Purpose |
|----------|--------|---------|---------|
| STATR | 0x00 | 0x40013800 | Status (TXE, TC, RXNE) |
| DATAR | 0x04 | 0x40013804 | Data (read/write) |
| BRR | 0x08 | 0x40013808 | Baud rate divider |
| CTLR1 | 0x0C | 0x4001380C | Control (UE, TE, RE) |

### Lines 64–66: Baud rate (in `src/uart.s`)

```asm
  li      t1, USART1_BASE
  li      a4, 0x0045             # BRR: 115200 baud @ 8 MHz
  sw      a4, 8(t1)              # USART_BRR
```

**BRR = 0x0045** means DIV_Mantissa = 4, DIV_Fraction = 5.

```
baud = 8,000,000 / (16 × (4 + 5/16)) = 8,000,000 / (16 × 4.3125) = 115,285
Error = 0.07% — well within UART tolerance.
```

### Lines 67–71: Enable USART (in `src/uart.s`)

```asm
  li      a4, USART_UE
  ori     a4, a4, USART_TE
  ori     a4, a4, USART_RE
  sw      a4, 0x0C(t1)           # USART_CTLR1
```

This sets three bits in one write:
- **UE (bit 13)** — USART enable
- **TE (bit 3)** — Transmitter enable
- **RE (bit 2)** — Receiver enable

---

## Part 8: The Echo Loop

### Lines 58–62: main (in `src/main.s`)

```asm
main:
  jal     ra, usart_init
  la      a0, str_hello
  jal     ra, print_string
```

Call `usart_init`, then print the greeting string.

### Lines 63–80: main_loop (in `src/main.s`)

```asm
main_loop:
  jal     usart_rx           # Block until character received -> a0
```

`usart_rx` spins until RXNE is set, then reads the byte into a0.

```asm
  li      t0, 0x08               # Backspace
  beq     a0, t0, handle_backspace
  li      t0, 0x7F               # DEL
  beq     a0, t0, handle_backspace
  li      t0, '\r'               # Enter
  beq     a0, t0, handle_enter
```

Check for special characters. Backspace (0x08) and DEL (0x7F) both trigger
the backspace handler. Enter (\r) triggers the enter handler.

```asm
  la      t1, L_input_len
  lw      t2, 0(t1)
  li      a4, INPUT_BUF_SIZE
  bge     t2, a4, main_loop      # Ignore if buffer full
```

If the buffer is full (32 chars), ignore further input.

```asm
  la      a4, L_input_buf
  add     a4, a4, t2
  sb      a0, 0(a4)              # Store character
  addi    t2, t2, 1
  sw      t2, 0(t1)              # Increment length
  jal     usart_tx           # Echo character
  j       main_loop
```

Store the character, increment the count, echo it back, loop.

### Lines 170–184: handle_backspace (in `src/uart.s`)

```asm
handle_backspace:
  la      t1, L_input_len
  lw      t2, 0(t1)
  beqz    t2, main_loop          # If empty, ignore
  addi    t2, t2, -1
  sw      t2, 0(t1)              # Decrement length
```

Decrement the buffer length. If already empty, ignore.

```asm
  li      a0, '\b'
  jal     ra, usart_tx
  li      a0, ' '
  jal     ra, usart_tx
  li      a0, '\b'
  jal     usart_tx
  j       main_loop
```

Send `\b \b` to erase the character on the terminal (back over the character,
print a space, back again).

### Lines 193–205: handle_enter (in `src/uart.s`)

```asm
handle_enter:
  li      a0, '\r'
  jal     usart_tx
  li      a0, '\n'
  jal     usart_tx
  la      t1, L_input_len
  sw      zero, 0(t1)            # Reset buffer
  la      a0, str_prompt
  jal     print_string       # Print "> " prompt
  j       main_loop
```

Send `\r\n`, reset the buffer length, print a new prompt.

---

## Part 9: Transmit, Receive, and Print

### Lines 83–118: usart_tx (in `src/uart.s`)

```asm
usart_tx:
  addi    sp, sp, -16
  sw      s0, 0(sp)
  sw      s1, 4(sp)
```

Save s0 and s1 on the stack (callee-saved registers).

```asm
  li      s0, USART1_BASE
  li      s1, AFIO_BASE
```

Keep these base addresses in saved registers across the function.

```asm
  # Switch remap to TX mode
  lw      a4, 0x0C(s0)           # Read USART_CTLR1
  andi    a4, a4, ~USART_RE      # Disable RX
  sw      a4, 0x0C(s0)

  lw      a4, 4(s1)              # Read AFIO_PCFR1
  andi    a4, a4, ~(1 << 2)      # Clear USART1_REMAP
  li      t2, (1 << 21)
  or      a4, a4, t2             # Set HIGH_BIT_REMAP
  sw      a4, 4(s1)
```

Before transmitting, we must:
1. Disable the receiver (RE=0)
2. Set AFIO to TX mode (Remap 10: HIGH_BIT=1, REMAP=0)

This is the dynamic remap — toggling AFIO to switch PD6 between TX and RX
functions.

```asm
.L_tx_wait_txe:
  lw      a4, 0(s0)              # Read USART_STATR
  andi    a4, a4, USART_TXE
  beqz    a4, .L_tx_wait_txe     # Wait until TXE=1
```

Spin until the transmit data register is empty.

```asm
  sb      a0, 4(s0)              # Write byte to USART_DATAR
```

Send the byte.

```asm
.L_tx_wait_tc:
  lw      a4, 0(s0)              # Read USART_STATR
  andi    a4, a4, USART_TC
  beqz    a4, .L_tx_wait_tc      # Wait until TC=1
```

Spin until transmission is complete (shift register empty too).

```asm
  # Switch remap back to RX mode
  lw      a4, 4(s1)              # Read AFIO_PCFR1
  li      t2, ~(1 << 21)
  and     a4, a4, t2             # Clear HIGH_BIT_REMAP
  ori     a4, a4, (1 << 2)       # Set USART1_REMAP
  sw      a4, 4(s1)

  lw      a4, 0x0C(s0)           # Read USART_CTLR1
  ori     a4, a4, USART_RE       # Re-enable RX
  sw      a4, 0x0C(s0)
```

After transmitting, restore AFIO to RX mode (Remap 01) and re-enable the
receiver.

```asm
  lw      s1, 4(sp)
  lw      s0, 0(sp)
  addi    sp, sp, 16
  ret
```

Restore saved registers and return.

### Lines 127–135: usart_rx (in `src/uart.s`)

```asm
usart_rx:
  li      t1, USART1_BASE
.L_rx_wait_rxne:
  lw      a4, 0(t1)              # Read USART_STATR
  andi    a4, a4, USART_RXNE
  beqz    a4, .L_rx_wait_rxne    # Wait until RXNE=1
  lb      a0, 4(t1)              # Read byte from USART_DATAR
  ret
```

Spin until data is received, then read it. Simple.

### Lines 144–161: print_string (in `src/uart.s`)

```asm
print_string:
  addi    sp, sp, -16
  sw      ra, 0(sp)
  sw      s0, 4(sp)
  mv      s0, a0
.L_print_loop:
  lb      a0, 0(s0)
  beqz    a0, .L_print_end
  jal     ra, usart_tx
  addi    s0, s0, 1
  j       .L_print_loop
.L_print_end:
  lw      s0, 4(sp)
  lw      ra, 0(sp)
  addi    sp, sp, 16
  ret
```

Loop through a null-terminated string, sending each byte via `usart_tx`.

---

## Part 10: Dynamic AFIO Remap

The Ouroboros Badge uses PD6 for USART1 TX and PD1 for USART1 RX. However, the CH32V003's AFIO register cannot map both of these pins to USART1 simultaneously:

| HIGH_BIT_REMAP (bit 21) | USART1_REMAP (bit 2) | TX | RX |
|-------|----------|----|----|
| 0 | 0 | PD5 | PD6 |
| 0 | 1 | PD0 | PD1 |
| 1 | 0 | PD6 | PD5 |
| 1 | 1 | PC0 | PC1 |

Because of this limitation, the firmware dynamically toggles AFIO on every byte to operate in half-duplex:
- **Before TX:** Set Remap=10 (TX on PD6, RX on PD5 — ignored)
- **After TX:** Set Remap=01 (RX on PD1, TX on PD0 — ignored)

This is implemented in `usart_tx` which saves/restores AFIO state. The
overhead is ~20 instructions per byte — negligible at 115200 baud.

---

## Part 11: Building, Flashing, and Debugging

### Build

```bash
make
```

### Flash

```bash
make flash
```

### Debug with GDB

```bash
make debug    # Terminal 1: start OpenOCD
make gdb      # Terminal 2: connect GDB
```

### Useful GDB commands

```
break main
break usart_tx
break usart_rx
continue
stepi
x/10i $pc
x/16x 0x40013800     # Dump USART1 registers
x/16x 0x40021018     # Dump RCC_APB2PCENR
info registers
monitor reset halt
```

---

## Summary

This firmware is a UART terminal that:
1. Sets up 8 MHz clock from 24 MHz HSI
2. Enables GPIOD + USART1 + AFIO clocks
3. Configures PD6 as TX (AF push-pull) and PD1 as RX (input pull-up)
4. Sets AFIO remap for RX on PD1 (Remap 01)
5. Configures USART1 for 115200 8N1
6. Prints a greeting, then echoes typed characters
7. Handles backspace and enter
8. Dynamically remaps AFIO on every byte to allow half-duplex operation, bypassing the CH32V003's pin mapping constraints.
