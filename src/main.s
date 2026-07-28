# ==============================================================================
# Project:       0x00-uart
# Author:        Kevin Thomas
# E-Mail:        ket189@pitt.edu
# Version:       1.0.0
# Date:          2026-07-26
# Target Device: CH32V003
# Clock Freq:    8 MHz
# Toolchain:     riscv64-unknown-elf-as, riscv64-unknown-elf-ld
# Description:   UART terminal for CH32V003. 115200 8N1, dynamic USART1 remap
#                (TX=PD6, RX=PD1). Echoes typed characters, handles backspace
#                and enter.
# ==============================================================================

# ==============================================================================
# SECTION:     Register definitions and .text setup
# ==============================================================================
  .include "regs.s"                     # CH32V003 peripheral register defs
  .equ INPUT_BUF_SIZE, 32               # maximum input buffer length

# ==============================================================================
# SECTION:     .rodata  (read-only string constants)
# ==============================================================================
  .section .rodata                      # read-only data section
  .align 2                              # align to 4-byte boundary
str_hello:
  .asciz "\r\nUART Terminal\r\n> "      # greeting string
  .globl str_prompt                     # export prompt string
str_prompt:
  .asciz "> "                           # prompt string

# ==============================================================================
# SECTION:     .bss  (file-private statics)
# ==============================================================================
  .section .bss                         # uninitialized data section
  .balign 4                             # align to 4-byte boundary
L_input_buf:
  .space INPUT_BUF_SIZE                 # uint8_t L_input_buf[INPUT_BUF_SIZE]
  .globl L_input_len                    # export buffer length symbol
L_input_len:
  .space 4                              # uint32_t L_input_len

# ==============================================================================
# SECTION:     .text
# ==============================================================================
  .section .text                        # executable code section
  .align 1                              # align to 2-byte boundary

# ==============================================================================
# SUBROUTINE:  main
# ==============================================================================
# Description: Initialise USART1, print greeting, then echo loop.
# ------------------------------------------------------------------------------
# Parameters:  None
# Returns:     None (infinite loop)
# ==============================================================================
  .globl main                           # export main symbol
main:
  jal     usart_init                    # configure USART1 for 115200 8N1
  la      a0, str_hello                 # load greeting string
  jal     print_string                  # print greeting
  .globl main_loop                      # export main_loop symbol
main_loop:
  jal     usart_rx                      # block until char received -> a0
  li      t0, 0x08                      # load backspace character
  beq     a0, t0, handle_backspace      # jump to backspace handler
  li      t0, 0x7F                      # load DEL character
  beq     a0, t0, handle_backspace      # jump to backspace handler
  li      t0, '\r'                      # load enter character
  beq     a0, t0, handle_enter          # jump to enter handler
  la      t1, L_input_len               # load buffer length address
  lw      t2, 0(t1)                     # read current buffer length
  li      a4, INPUT_BUF_SIZE            # load max buffer size
  bge     t2, a4, main_loop             # ignore if buffer is full
  la      a4, L_input_buf               # load buffer base address
  add     a4, a4, t2                    # offset by current length
  sb      a0, 0(a4)                     # store character in buffer
  addi    t2, t2, 1                     # increment length
  sw      t2, 0(t1)                     # save new length
  jal     usart_tx                      # echo character
  j       main_loop                     # loop indefinitely
