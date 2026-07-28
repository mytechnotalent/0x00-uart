# ==============================================================================
# Project:       0x00-uart
# Author:        Kevin Thomas
# E-Mail:        ket189@pitt.edu
# Version:       1.0.0
# Date:          2026-07-26
# Target Device: CH32V003
# Clock Freq:    8 MHz
# Toolchain:     riscv64-unknown-elf-as, riscv64-unknown-elf-ld
# Description:   UART peripheral routines.
# ==============================================================================

# ==============================================================================
# SECTION:     Register definitions and .text setup
# ==============================================================================
  .include "regs.s"                     # CH32V003 peripheral register defs

# ==============================================================================
# SECTION:     .text  (executable code)
# ==============================================================================
  .section .text                        # executable code section
  .globl usart_init
  .globl usart_tx
  .globl usart_rx
  .globl print_string

# ==============================================================================
# SUBROUTINE:  usart_init
# ==============================================================================
# Description: Configure USART1 for 115200 8N1 with dynamic remap.
#              TX=PD6 (AF Output Push-Pull 50 MHz), RX=PD1 (Input Pull-up).
# ------------------------------------------------------------------------------
# Parameters:  None
# Returns:     None
# ==============================================================================
usart_init:
  li      t1, RCC_BASE                  # load RCC base address
  lw      a4, RCC_APB2PCENR(t1)         # read APB2 clock enable reg
  li      t2, 0x4021                    # USART1EN | IOPDEN | AFIOEN
  or      a4, a4, t2                    # set clock enable bits
  sw      a4, RCC_APB2PCENR(t1)         # write back to RCC
  li      t1, GPIOD_BASE                # load GPIOD base address
  lw      a4, GPIO_CFGLR(t1)            # read GPIOD config register
  li      t2, ~(0xF << 24)              # clear PD6 config mask
  and     a4, a4, t2                    # apply clear mask
  li      t2, (0xA << 24)               # PD6: AF Output Push-Pull
  or      a4, a4, t2                    # set PD6 config
  li      t2, ~(0xF << 4)               # clear PD1 config mask
  and     a4, a4, t2                    # apply clear mask
  li      t2, (0x8 << 4)                # PD1: Input Pull-up
  or      a4, a4, t2                    # set PD1 config
  sw      a4, GPIO_CFGLR(t1)            # write back to GPIOD
  li      a4, (1 << 6)                  # load PD6 bit
  sw      a4, GPIO_BSHR(t1)             # set PD6 high (idle)
  lw      a4, GPIO_OUTDR(t1)            # read GPIOD output register
  ori     a4, a4, (1 << 1)              # enable PD1 pull-up
  sw      a4, GPIO_OUTDR(t1)            # write back to GPIOD
  li      t1, AFIO_BASE                 # load AFIO base address
  lw      a4, AFIO_PCFR1(t1)            # read AFIO remap register
  li      t2, ~(1 << 21)                # clear HIGH_BIT_REMAP bit
  and     a4, a4, t2                    # apply clear mask
  ori     a4, a4, (1 << 2)              # set USART1_REMAP bit
  sw      a4, AFIO_PCFR1(t1)            # write back to AFIO
  li      t1, USART1_BASE               # load USART1 base address
  li      a4, 0x0045                    # BRR: 115200 baud @ 8 MHz
  sw      a4, USART_BRR(t1)             # write baud rate register
  li      a4, USART_UE                  # enable USART
  ori     a4, a4, USART_TE              # enable TX
  ori     a4, a4, USART_RE              # enable RX
  sw      a4, USART_CTLR1(t1)           # write control register
  ret                                   # return to caller

# ==============================================================================
# SUBROUTINE:  usart_tx
# ==============================================================================
# Description: Transmit a single byte. Dynamically remaps AFIO for TX mode,
#              waits for TXE, sends byte, waits for TC, then remaps back to RX.
# ------------------------------------------------------------------------------
# Parameters:  a0 = byte to transmit
# Returns:     None
# ==============================================================================
usart_tx:
  addi    sp, sp, -16                   # allocate stack space
  sw      s0, 0(sp)                     # save s0
  sw      s1, 4(sp)                     # save s1
  li      s0, USART1_BASE               # load USART1 base address
  li      s1, AFIO_BASE                 # load AFIO base address
  lw      a4, USART_CTLR1(s0)           # read USART control register
  andi    a4, a4, ~USART_RE             # clear RE bit (disable RX)
  sw      a4, USART_CTLR1(s0)           # write back to USART
  lw      a4, AFIO_PCFR1(s1)            # read AFIO remap register
  andi    a4, a4, ~(1 << 2)             # clear USART1_REMAP bit
  li      t2, (1 << 21)                 # load HIGH_BIT_REMAP bit
  or      a4, a4, t2                    # set HIGH_BIT_REMAP bit
  sw      a4, AFIO_PCFR1(s1)            # write back to AFIO (TX mode)
.L_tx_wait_txe:
  lw      a4, USART_STATR(s0)           # read USART status register
  andi    a4, a4, USART_TXE             # mask TXE bit
  beqz    a4, .L_tx_wait_txe            # wait until TXE is set
  sb      a0, USART_DATAR(s0)           # write byte to transmit
.L_tx_wait_tc:
  lw      a4, USART_STATR(s0)           # read USART status register
  andi    a4, a4, USART_TC              # mask TC bit
  beqz    a4, .L_tx_wait_tc             # wait until TC is set
  lw      a4, AFIO_PCFR1(s1)            # read AFIO remap register
  li      t2, ~(1 << 21)                # load HIGH_BIT_REMAP mask
  and     a4, a4, t2                    # clear HIGH_BIT_REMAP bit
  ori     a4, a4, (1 << 2)              # set USART1_REMAP bit
  sw      a4, AFIO_PCFR1(s1)            # write back to AFIO (RX mode)
  lw      a4, USART_CTLR1(s0)           # read USART control register
  ori     a4, a4, USART_RE              # set RE bit (enable RX)
  sw      a4, USART_CTLR1(s0)           # write back to USART
  lw      s1, 4(sp)                     # restore s1
  lw      s0, 0(sp)                     # restore s0
  addi    sp, sp, 16                    # deallocate stack space
  ret                                   # return to caller

# ==============================================================================
# SUBROUTINE:  usart_rx
# ==============================================================================
# Description: Blocking receive — spin until RXNE is set, then read byte.
# ------------------------------------------------------------------------------
# Parameters:  None
# Returns:     a0 = received byte
# ==============================================================================
usart_rx:
  li      t1, USART1_BASE               # load USART1 base address
.L_rx_wait_rxne:
  lw      a4, USART_STATR(t1)           # read USART status register
  andi    a4, a4, USART_RXNE            # mask RXNE bit
  beqz    a4, .L_rx_wait_rxne           # wait until RXNE is set
  lb      a0, USART_DATAR(t1)           # read received byte
  ret                                   # return to caller

# ==============================================================================
# SUBROUTINE:  print_string
# ==============================================================================
# Description: Print a null-terminated string to USART1.
# ------------------------------------------------------------------------------
# Parameters:  a0 = pointer to string
# Returns:     None
# ==============================================================================
print_string:
  addi    sp, sp, -16                   # allocate stack space
  sw      ra, 0(sp)                     # save return address
  sw      s0, 4(sp)                     # save s0
  addi    s0, a0, 0                     # copy string pointer to s0
.L_print_loop:
  lb      a0, 0(s0)                     # load character from string
  beqz    a0, .L_print_end              # if null terminator, end loop
  jal     usart_tx                      # transmit character
  addi    s0, s0, 1                     # increment string pointer
  j       .L_print_loop                 # repeat for next character
.L_print_end:
  lw      s0, 4(sp)                     # restore s0
  lw      ra, 0(sp)                     # restore return address
  addi    sp, sp, 16                    # deallocate stack space
  ret                                   # return to caller

# ==============================================================================
# SUBROUTINE:  handle_backspace
# ==============================================================================
# Description: Remove last character from buffer, send \b \b \b to terminal.
# ------------------------------------------------------------------------------
# Parameters:  None
# Returns:     None
# ==============================================================================
  .globl handle_backspace
handle_backspace:
  la      t1, L_input_len               # load buffer length address
  lw      t2, 0(t1)                     # read current buffer length
  beqz    t2, main_loop                 # ignore if buffer is empty
  addi    t2, t2, -1                    # decrement length
  sw      t2, 0(t1)                     # save new length
  li      a0, '\b'                      # load backspace character
  jal     usart_tx                      # send backspace
  li      a0, ' '                       # load space character
  jal     usart_tx                      # send space
  li      a0, '\b'                      # load backspace character
  jal     usart_tx                      # send backspace
  j       main_loop                     # return to main loop

# ==============================================================================
# SUBROUTINE:  handle_enter
# ==============================================================================
# Description: Echo \r\n, reset buffer, print new prompt.
# ------------------------------------------------------------------------------
# Parameters:  None
# Returns:     None
# ==============================================================================
  .globl handle_enter
handle_enter:
  li      a0, '\r'                      # load carriage return
  jal     usart_tx                      # send carriage return
  li      a0, '\n'                      # load line feed
  jal     usart_tx                      # send line feed
  la      t1, L_input_len               # load buffer length address
  sw      zero, 0(t1)                   # reset buffer length to 0
  la      a0, str_prompt                # load prompt string
  jal     print_string                  # print prompt
  j       main_loop                     # return to main loop
