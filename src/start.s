# ==============================================================================
# Project:       0x00-uart
# Author:        Kevin Thomas
# E-Mail:        ket189@pitt.edu
# Version:       1.0.0
# Date:          2026-07-26
# Target Device: CH32V003
# Clock Freq:    8 MHz
# Toolchain:     riscv64-unknown-elf-as, riscv64-unknown-elf-ld
# Description:   Reset vector table and startup code. Mirrors the WCH
#                startup_ch32v00x.S: sets gp/sp, copies .data, clears .bss,
#                configures mstatus / interrupt CSRs / mtvec, brings the core
#                up to 8 MHz (HSI/3), then jumps to main().
# ==============================================================================

# ==============================================================================
# SECTION:     Register definitions
# ==============================================================================
  .include "regs.s"                       # CH32V003 peripheral register defs

# ==============================================================================
# SECTION:     .init  (reset vector table)
# ==============================================================================
  .section .init, "ax", @progbits
  .globl _start
  .align 2
_start:
  .option norvc
  j       handle_reset                  # 0  reset
  .word   0                             # 1
  .word   NMI_Handler                   # 2  NMI
  .word   HardFault_Handler             # 3  Hard fault
  .word   0                             # 4
  .word   0                             # 5
  .word   0                             # 6
  .word   0                             # 7
  .word   0                             # 8
  .word   0                             # 9
  .word   0                             # 10
  .word   0                             # 11
  .word   SysTick_Handler               # 12 SysTick
  .word   0                             # 13
  .word   SW_Handler                    # 14 software
  .word   0                             # 15
  .word   WWDG_IRQHandler               # 16
  .word   PVD_IRQHandler                # 17
  .word   FLASH_IRQHandler              # 18
  .word   RCC_IRQHandler                # 19
  .word   EXTI7_0_IRQHandler            # 20
  .word   AWU_IRQHandler                # 21
  .word   DMA1_Channel1_IRQHandler      # 22
  .word   DMA1_Channel2_IRQHandler      # 23
  .word   DMA1_Channel3_IRQHandler      # 24
  .word   DMA1_Channel4_IRQHandler      # 25
  .word   DMA1_Channel5_IRQHandler      # 26
  .word   DMA1_Channel6_IRQHandler      # 27
  .word   DMA1_Channel7_IRQHandler      # 28
  .word   ADC1_IRQHandler               # 29
  .word   I2C1_EV_IRQHandler            # 30
  .word   I2C1_ER_IRQHandler            # 31
  .word   USART1_IRQHandler             # 32 USART1
  .word   SPI1_IRQHandler               # 33
  .word   TIM1_BRK_IRQHandler           # 34
  .word   TIM1_UP_IRQHandler            # 35
  .word   TIM1_TRG_COM_IRQHandler       # 36
  .word   TIM1_CC_IRQHandler            # 37
  .word   TIM2_IRQHandler               # 38 TIM2
  .option rvc

# ==============================================================================
# SUBROUTINE:  handle_reset
# ==============================================================================
# Description: Reset handler: sets gp/sp, copies .data, clears .bss,
#              configures mstatus/interrupt CSRs, boots to 8 MHz, jumps to main.
# ------------------------------------------------------------------------------
# Parameters:  None
# Returns:     None
# ==============================================================================
  .section .text.handle_reset, "ax", @progbits
  .globl handle_reset
  .align 1
handle_reset:
.option push                            # save current option state
.option norelax                         # disable linker relaxation for gp
  la      gp, __global_pointer$         # set global pointer
.option pop                             # restore previous option state
  la      sp, _eusrstack                # set stack pointer
  # ---- copy .data (LMA -> VMA) -------------------------------------------
  la      a0, _data_lma                 # source address in flash
  la      a1, _data_vma                 # destination address in RAM
  la      a2, _edata                    # end address in RAM
  bgeu    a1, a2, 2f                    # skip if .data is empty
1:
  lw      t0, 0(a0)                     # read word from flash
  sw      t0, 0(a1)                     # write word to RAM
  addi    a0, a0, 4                     # advance source pointer
  addi    a1, a1, 4                     # advance destination pointer
  bltu    a1, a2, 1b                    # loop until .data copied
2:
  # ---- clear .bss --------------------------------------------------------
  la      a0, _sbss                     # start of .bss
  la      a1, _ebss                     # end of .bss
  bgeu    a0, a1, 2f                    # skip if .bss is empty
1:
  sw      zero, 0(a0)                   # zero one word
  addi    a0, a0, 4                     # advance pointer
  bltu    a0, a1, 1b                    # loop until .bss cleared
2:
  # ---- privileged mode + interrupt config --------------------------------
.ifndef SIMULATION
  li      t0, 0x1880                    # MPP=Machine, MPIE=1
  csrw    mstatus, t0                   # set machine status register
  li      t0, 0x3                       # enable HW stack + interrupt nesting
  csrw    0x804, t0                     # write INTSYSCR CSR
  la      t0, _start                    # vector table base
  ori     t0, t0, 3                     # absolute-address vectored mode
  csrw    mtvec, t0                     # set machine trap vector
.endif
  # ---- bring core to 8 MHz (HSI / 3), 0 flash wait states ----------------
  jal     boot_clock_8mhz               # configure clock for 8 MHz
  # ---- enter application -------------------------------------------------
  jal     main                          # jump to application entry
1:
  j       1b                            # infinite loop if main returns

# ==============================================================================
# SUBROUTINE:  boot_clock_8mhz
# ==============================================================================
# Description: Replicate the framework SystemInit for 8 MHz HSI so main()
#              runs at exactly the clock init_hardware() assumes
#              (BRR=0x45 = 115200 @ 8 MHz).
# ------------------------------------------------------------------------------
# Parameters:  None
# Returns:     None
# ==============================================================================
boot_clock_8mhz:
  # select HSI as system clock (SW = 00), then wait until SWS == 00
  li      t0, RCC_BASE                  # RCC peripheral base address
  lw      t1, RCC_CFGR0(t0)             # read clock configuration
  andi    t1, t1, -4                    # clear SW[1:0]
  sw      t1, RCC_CFGR0(t0)             # write back
1:
  lw      t1, RCC_CFGR0(t0)             # read clock status
  andi    t1, t1, RCC_SWS               # mask SWS bits
  bnez    t1, 1b                        # wait until HSI selected
  # flash latency 0
  li      t2, FLASH_BASE                # flash peripheral base address
  lw      t1, FLASH_ACTLR(t2)           # read access control
  andi    t1, t1, -4                    # clear LATENCY[2:0] -> 0 WS
  sw      t1, FLASH_ACTLR(t2)           # write back
  # HCLK = SYSCLK / 3  (24 MHz HSI -> 8 MHz)
  lw      t1, RCC_CFGR0(t0)             # read clock configuration
  li      a0, 0xFFFFFF0F                # ~RCC_HPRE mask
  and     t1, t1, a0                    # clear HPRE bits
  ori     t1, t1, RCC_HPRE_DIV3         # set prescaler /3
  sw      t1, RCC_CFGR0(t0)             # write back
  ret                                   # return to caller

# ==============================================================================
# Default interrupt handlers (all unused vectors trap here).
# ==============================================================================
  .section .text.default_handlers, "ax", @progbits
  .globl NMI_Handler
  .globl HardFault_Handler
  .globl SysTick_Handler
  .globl SW_Handler
  .globl WWDG_IRQHandler, PVD_IRQHandler, FLASH_IRQHandler, RCC_IRQHandler
  .globl EXTI7_0_IRQHandler, AWU_IRQHandler
  .globl DMA1_Channel1_IRQHandler, DMA1_Channel2_IRQHandler
  .globl DMA1_Channel3_IRQHandler, DMA1_Channel4_IRQHandler
  .globl DMA1_Channel5_IRQHandler, DMA1_Channel6_IRQHandler
  .globl DMA1_Channel7_IRQHandler, ADC1_IRQHandler
  .globl I2C1_EV_IRQHandler, I2C1_ER_IRQHandler, SPI1_IRQHandler
  .globl USART1_IRQHandler
  .globl TIM1_BRK_IRQHandler, TIM1_UP_IRQHandler
  .globl TIM1_TRG_COM_IRQHandler, TIM1_CC_IRQHandler
  .globl TIM2_IRQHandler
NMI_Handler:
HardFault_Handler:
SysTick_Handler:
SW_Handler:
WWDG_IRQHandler:
PVD_IRQHandler:
FLASH_IRQHandler:
RCC_IRQHandler:
EXTI7_0_IRQHandler:
AWU_IRQHandler:
DMA1_Channel1_IRQHandler:
DMA1_Channel2_IRQHandler:
DMA1_Channel3_IRQHandler:
DMA1_Channel4_IRQHandler:
DMA1_Channel5_IRQHandler:
DMA1_Channel6_IRQHandler:
DMA1_Channel7_IRQHandler:
ADC1_IRQHandler:
I2C1_EV_IRQHandler:
I2C1_ER_IRQHandler:
SPI1_IRQHandler:
USART1_IRQHandler:
TIM1_BRK_IRQHandler:
TIM1_UP_IRQHandler:
TIM1_TRG_COM_IRQHandler:
TIM1_CC_IRQHandler:
TIM2_IRQHandler:
1:
  j       1b
