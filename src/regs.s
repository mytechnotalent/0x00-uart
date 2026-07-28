# ==============================================================================
# Project:       0x00-uart
# Author:        Kevin Thomas
# E-Mail:        ket189@pitt.edu
# Version:       1.0.0
# Date:          2026-07-26
# Target Device: CH32V003
# Clock Freq:    8 MHz
# Toolchain:     riscv64-unknown-elf-as, riscv64-unknown-elf-ld
# Description:   CH32V003 peripheral base / register / bit definitions.
# ==============================================================================

# ------------------------------------------------------------------------------
# Peripheral base addresses
# ------------------------------------------------------------------------------
  .equ RCC_BASE,             0x40021000
  .equ AFIO_BASE,            0x40010000
  .equ GPIOD_BASE,           0x40011400
  .equ USART1_BASE,          0x40013800
  .equ FLASH_BASE,           0x40022000

# ------------------------------------------------------------------------------
# Register offsets
# ------------------------------------------------------------------------------
  .equ GPIO_CFGLR,           0x00
  .equ GPIO_OUTDR,           0x0C
  .equ GPIO_BSHR,            0x10

  .equ AFIO_PCFR1,           0x04

  .equ USART_STATR,          0x00
  .equ USART_DATAR,          0x04
  .equ USART_BRR,            0x08
  .equ USART_CTLR1,          0x0C

  .equ RCC_CTLR,             0x00
  .equ RCC_CFGR0,            0x04
  .equ RCC_APB2PCENR,        0x18

  .equ FLASH_ACTLR,          0x00

# ------------------------------------------------------------------------------
# Bit definitions
# ------------------------------------------------------------------------------
  # RCC
  .equ RCC_SWS,              0x0000000C
  .equ RCC_HPRE_DIV3,        0x00000020

  # RCC clock-enable bits
  .equ RCC_APB2_AFIO,        0x00000001
  .equ RCC_APB2_GPIOD,       0x00000020
  .equ RCC_APB2_USART1,      0x00004000

  # USART STATR
  .equ USART_TXE,            0x0080
  .equ USART_TC,             0x0040
  .equ USART_RXNE,           0x0020

  # USART CTLR1
  .equ USART_RE,             0x0004
  .equ USART_TE,             0x0008
  .equ USART_RXNEIE,         0x0020
  .equ USART_UE,             0x2000
