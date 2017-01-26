/*
 * armboot - Startup Code for OMAP3530/ARM Cortex CPU-core
 *
 * Copyright (c) 2004	Texas Instruments <r-woodruff2@ti.com>
 *
 * Copyright (c) 2001	Marius Gröger <mag@sysgo.de>
 * Copyright (c) 2002	Alex Züpke <azu@sysgo.de>
 * Copyright (c) 2002	Gary Jennejohn <garyj@denx.de>
 * Copyright (c) 2003	Richard Woodruff <r-woodruff2@ti.com>
 * Copyright (c) 2003	Kshitij <kshitij@ti.com>
 * Copyright (c) 2006-2008 Syed Mohammed Khasim <x0khasim@ti.com>
 *
 * SPDX-License-Identifier:	GPL-2.0+
 */

#include <asm-offsets.h>
#include <config.h>
#include <asm/system.h>
#include <linux/linkage.h>
#include <asm/armv7.h>

/*************************************************************************
 *
 * Startup Code (reset vector)
 *
 * Do important init only if we don't start from memory!
 * Setup memory and board specific bits prior to relocation.
 * Relocate armboot to ram. Setup stack.
 *
 *************************************************************************/

	.globl	reset
	.globl	save_boot_params_ret
#ifdef CONFIG_ARMV7_LPAE
	.global	switch_to_hypervisor_ret
#endif

reset:
	/* Allow the board to save important registers */
	b	save_boot_params
save_boot_params_ret:
#ifdef CONFIG_ARMV7_LPAE
/*
 * check for Hypervisor support
 */
	mrc	p15, 0, r0, c0, c1, 1		@ read ID_PFR1
	and	r0, r0, #CPUID_ARM_VIRT_MASK	@ mask virtualization bits
	cmp	r0, #(1 << CPUID_ARM_VIRT_SHIFT)
	beq	switch_to_hypervisor
switch_to_hypervisor_ret:
#endif
	/*
	 * disable interrupts (FIQ and IRQ), also set the cpu to SVC32 mode,
	 * except if in HYP mode already
	 */
	mrs	r0, cpsr
	and	r1, r0, #0x1f		@ mask mode bits
	teq	r1, #0x1a		@ test for HYP mode
	bicne	r0, r0, #0x1f		@ clear all mode bits
	orrne	r0, r0, #0x13		@ set SVC mode
	orr	r0, r0, #0xc0		@ disable FIQ and IRQ
	msr	cpsr,r0

/*
 * Setup vector:
 * (OMAP4 spl TEXT_BASE is not 32 byte aligned.
 * Continue to use ROM code vector only in OMAP4 spl)
 */
#if !(defined(CONFIG_OMAP44XX) && defined(CONFIG_SPL_BUILD))
	/* Set V=0 in CP15 SCTLR register - for VBAR to point to vector */
	mrc	p15, 0, r0, c1, c0, 0	@ Read CP15 SCTLR Register
	bic	r0, #CR_V		@ V = 0
	mcr	p15, 0, r0, c1, c0, 0	@ Write CP15 SCTLR Register

	/* Set vector address in CP15 VBAR register */
	ldr	r0, =_start
	mcr	p15, 0, r0, c12, c0, 0	@Set VBAR
#endif

	/* the mask ROM code should have PLL and others stable */
#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	bl	cpu_init_cp15
#ifndef CONFIG_SKIP_LOWLEVEL_INIT_ONLY
	bl	cpu_init_crit
#endif
#endif

	bl LED1_ON
	bl LED2_ON
	bl LED3_ON
	bl LED4_ON

	bl DELAY

	bl LED1_OFF
	bl LED2_OFF
	bl LED3_OFF
	bl LED4_OFF
	bl	_main

/*------------------------------------------------------------------------------*/

ENTRY(c_runtime_cpu_setup)
/*
 * If I-cache is enabled invalidate it
 */
#ifndef CONFIG_SYS_ICACHE_OFF
	mcr	p15, 0, r0, c7, c5, 0	@ invalidate icache
	mcr     p15, 0, r0, c7, c10, 4	@ DSB
	mcr     p15, 0, r0, c7, c5, 4	@ ISB
#endif

	bx	lr

ENDPROC(c_runtime_cpu_setup)

/*************************************************************************
 *
 * void save_boot_params(u32 r0, u32 r1, u32 r2, u32 r3)
 *	__attribute__((weak));
 *
 * Stack pointer is not yet initialized at this moment
 * Don't save anything to stack even if compiled with -O0
 *
 *************************************************************************/
ENTRY(save_boot_params)
	b	save_boot_params_ret		@ back to my caller
ENDPROC(save_boot_params)
	.weak	save_boot_params

#ifdef CONFIG_ARMV7_LPAE
ENTRY(switch_to_hypervisor)
	b	switch_to_hypervisor_ret
ENDPROC(switch_to_hypervisor)
	.weak	switch_to_hypervisor
#endif

/*************************************************************************
 *
 * cpu_init_cp15
 *
 * Setup CP15 registers (cache, MMU, TLBs). The I-cache is turned on unless
 * CONFIG_SYS_ICACHE_OFF is defined.
 *
 *************************************************************************/
ENTRY(cpu_init_cp15)
	/*
	 * Invalidate L1 I/D
	 */
	mov	r0, #0			@ set up for MCR
	mcr	p15, 0, r0, c8, c7, 0	@ invalidate TLBs
	mcr	p15, 0, r0, c7, c5, 0	@ invalidate icache
	mcr	p15, 0, r0, c7, c5, 6	@ invalidate BP array
	mcr     p15, 0, r0, c7, c10, 4	@ DSB
	mcr     p15, 0, r0, c7, c5, 4	@ ISB

	/*
	 * disable MMU stuff and caches
	 */
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #0x00002000	@ clear bits 13 (--V-)
	bic	r0, r0, #0x00000007	@ clear bits 2:0 (-CAM)
	orr	r0, r0, #0x00000002	@ set bit 1 (--A-) Align
	orr	r0, r0, #0x00000800	@ set bit 11 (Z---) BTB
#ifdef CONFIG_SYS_ICACHE_OFF
	bic	r0, r0, #0x00001000	@ clear bit 12 (I) I-cache
#else
	orr	r0, r0, #0x00001000	@ set bit 12 (I) I-cache
#endif
	mcr	p15, 0, r0, c1, c0, 0

#ifdef CONFIG_ARM_ERRATA_716044
	mrc	p15, 0, r0, c1, c0, 0	@ read system control register
	orr	r0, r0, #1 << 11	@ set bit #11
	mcr	p15, 0, r0, c1, c0, 0	@ write system control register
#endif

#if (defined(CONFIG_ARM_ERRATA_742230) || defined(CONFIG_ARM_ERRATA_794072))
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 4		@ set bit #4
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif

#ifdef CONFIG_ARM_ERRATA_743622
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 6		@ set bit #6
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif

#ifdef CONFIG_ARM_ERRATA_751472
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 11	@ set bit #11
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif
#ifdef CONFIG_ARM_ERRATA_761320
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 21	@ set bit #21
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif

	mov	r5, lr			@ Store my Caller
	mrc	p15, 0, r1, c0, c0, 0	@ r1 has Read Main ID Register (MIDR)
	mov	r3, r1, lsr #20		@ get variant field
	and	r3, r3, #0xf		@ r3 has CPU variant
	and	r4, r1, #0xf		@ r4 has CPU revision
	mov	r2, r3, lsl #4		@ shift variant field for combined value
	orr	r2, r4, r2		@ r2 has combined CPU variant + revision

#ifdef CONFIG_ARM_ERRATA_798870
	cmp	r2, #0x30		@ Applies to lower than R3p0
	bge	skip_errata_798870      @ skip if not affected rev
	cmp	r2, #0x20		@ Applies to including and above R2p0
	blt	skip_errata_798870      @ skip if not affected rev

	mrc	p15, 1, r0, c15, c0, 0  @ read l2 aux ctrl reg
	orr	r0, r0, #1 << 7         @ Enable hazard-detect timeout
	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_l2aux_ctrl
	isb				@ Recommended ISB after l2actlr update
	pop	{r1-r5}			@ Restore the cpu info - fall through
skip_errata_798870:
#endif

#ifdef CONFIG_ARM_ERRATA_801819
	cmp	r2, #0x24		@ Applies to lt including R2p4
	bgt	skip_errata_801819      @ skip if not affected rev
	cmp	r2, #0x20		@ Applies to including and above R2p0
	blt	skip_errata_801819      @ skip if not affected rev
	mrc	p15, 0, r0, c0, c0, 6	@ pick up REVIDR reg
	and	r0, r0, #1 << 3		@ check REVIDR[3]
	cmp	r0, #1 << 3
	beq	skip_errata_801819	@ skip erratum if REVIDR[3] is set

	mrc	p15, 0, r0, c1, c0, 1	@ read auxilary control register
	orr	r0, r0, #3 << 27	@ Disables streaming. All write-allocate
					@ lines allocate in the L1 or L2 cache.
	orr	r0, r0, #3 << 25	@ Disables streaming. All write-allocate
					@ lines allocate in the L1 cache.
	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_acr
	pop	{r1-r5}			@ Restore the cpu info - fall through
skip_errata_801819:
#endif

#ifdef CONFIG_ARM_ERRATA_454179
	cmp	r2, #0x21		@ Only on < r2p1
	bge	skip_errata_454179

	mrc	p15, 0, r0, c1, c0, 1	@ Read ACR
	orr	r0, r0, #(0x3 << 6)	@ Set DBSM(BIT7) and IBE(BIT6) bits
	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_acr
	pop	{r1-r5}			@ Restore the cpu info - fall through

skip_errata_454179:
#endif

#ifdef CONFIG_ARM_ERRATA_430973
	cmp	r2, #0x21		@ Only on < r2p1
	bge	skip_errata_430973

	mrc	p15, 0, r0, c1, c0, 1	@ Read ACR
	orr	r0, r0, #(0x1 << 6)	@ Set IBE bit
	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_acr
	pop	{r1-r5}			@ Restore the cpu info - fall through

skip_errata_430973:
#endif

#ifdef CONFIG_ARM_ERRATA_621766
	cmp	r2, #0x21		@ Only on < r2p1
	bge	skip_errata_621766

	mrc	p15, 0, r0, c1, c0, 1	@ Read ACR
	orr	r0, r0, #(0x1 << 5)	@ Set L1NEON bit
	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_acr
	pop	{r1-r5}			@ Restore the cpu info - fall through

skip_errata_621766:
#endif

	mov	pc, r5			@ back to my caller
ENDPROC(cpu_init_cp15)

#if !defined(CONFIG_SKIP_LOWLEVEL_INIT) && \
	!defined(CONFIG_SKIP_LOWLEVEL_INIT_ONLY)
/*************************************************************************
 *
 * CPU_init_critical registers
 *
 * setup important registers
 * setup memory timing
 *
 *************************************************************************/
ENTRY(cpu_init_crit)
	/*
	 * Jump to board specific initialization...
	 * The Mask ROM will have already initialized
	 * basic memory. Go here to bump up clock rate and handle
	 * wake up conditions.
	 */
	b	lowlevel_init		@ go setup pll,mux,memory
ENDPROC(cpu_init_crit)
#endif

ENTRY(LED1_ON)
	/*
	 * GPM4CON Address = 0x110002E0
	 * GPM4DAT Address = 0x110002E4
	 */
	ldr r0, =0x110002E0
	ldr r1, [r0]		//读出GPM4CON的值
	bic r1, r1, #0xf	//将GPM4CON[0:3]清零
	orr r1, r1, #0x1	//将GPM4_0设置为输出引脚
	str r1, [r0]		//将设置的值写回GPM4CON

	ldr r0, =0x110002E4
	ldr r1, [r0]		//读出GPM4DAT的值
	bic r1, r1, #0		//将CPM4DAT的第[0]清零，清零就是输出低电平了
	str r1, [r0]		//将设置的值写回GPM4DAT

	mov pc, lr			//最后不要忘记这一条，将lr的值写回pc，将程序跳回到执行LED1_ON之后继续执行
ENDPROC(LED1_ON)

ENTRY(LED2_ON)
	/*
	 * GPM4CON Address = 0x110002E0
	 * GPM4DAT Address = 0x110002E4
	 */
	ldr r0, =0x110002E0
	ldr r1, [r0]		//读出GPM4CON的值
	bic r1, r1, #0xf0	//将GPM4CON[4:7]清零
	orr r1, r1, #0x10	//将GPM4_1设置为输出引脚
	str r1, [r0]		//将设置的值写回GPM4CON

	ldr r0, =0x110002E4
	ldr r1, [r0]		//读出GPM4DAT的值
	bic r1, r1, #2		//将CPM4DAT的第[1]清零，清零就是输出低电平了
	str r1, [r0]		//将设置的值写回GPM4DAT

	mov pc, lr			//最后不要忘记这一条，将lr的值写回pc，将程序跳回到执行LED2_ON之后继续执行
ENDPROC(LED2_ON)

ENTRY(LED3_ON)
	/*
	 * GPM4CON Address = 0x110002E0
	 * GPM4DAT Address = 0x110002E4
	 */
	ldr r0, =0x110002E0
	ldr r1, [r0]		//读出GPM4CON的值
	bic r1, r1, #0xf00	//将GPM4CON[8:11]清零
	orr r1, r1, #0x100	//将GPM4_2设置为输出引脚
	str r1, [r0]		//将设置的值写回GPM4CON

	ldr r0, =0x110002E4
	ldr r1, [r0]		//读出GPM4DAT的值
	bic r1, r1, #4		//将CPM4DAT的第[2]清零，清零就是输出低电平了
	str r1, [r0]		//将设置的值写回GPM4DAT

	mov pc, lr			//最后不要忘记这一条，将lr的值写回pc，将程序跳回到执行LED3_ON之后继续执行
ENDPROC(LED3_ON)

ENTRY(LED4_ON)
	/*
	 * GPM4CON Address = 0x110002E0
	 * GPM4DAT Address = 0x110002E4
	 */
	ldr r0, =0x110002E0
	ldr r1, [r0]		//读出GPM4CON的值
	bic r1, r1, #0xf000	//将GPM4CON[12:15]清零
	orr r1, r1, #0x1000	//将GPM4_3设置为输出引脚
	str r1, [r0]		//将设置的值写回GPM4CON

	ldr r0, =0x110002E4
	ldr r1, [r0]		//读出GPM4DAT的值
	bic r1, r1, #8		//将CPM4DAT的第[3]位清零，清零就是输出低电平了
	str r1, [r0]		//将设置的值写回GPM4DAT

	mov pc, lr			//最后不要忘记这一条，将lr的值写回pc，将程序跳回到执行LED4_ON之后继续执行
ENDPROC(LED4_ON)

ENTRY(LED1_OFF)
	/*
	 * GPM4CON Address = 0x110002E0
	 * GPM4DAT Address = 0x110002E4
	 */
	ldr r0, =0x110002E0
	ldr r1, [r0]		//读出GPM4CON的值
	bic r1, r1, #0xf	//将GPM4CON[0:3]清零
	orr r1, r1, #0x1	//将GPM4_0设置为输出引脚
	str r1, [r0]		//将设置的值写回GPM4CON

	ldr r0, =0x110002E4
	ldr r1, [r0]		//读出GPM4DAT的值
	bic r1, r1, #1		//将CPM4DAT的第[0]位清零，清零就是输出低电平了
	orr r1, r1, #1      //将GPM4DAT的第[0]为设置为1,输出高电平，LED灯熄灭
	str r1, [r0]		//将设置的值写回GPM4DAT

	mov pc, lr			//最后不要忘记这一条，将lr的值写回pc，将程序跳回到执行LED1_OFF之后继续执行
ENDPROC(LED1_OFF)

ENTRY(LED2_OFF)
	/*
	 * GPM4CON Address = 0x110002E0
	 * GPM4DAT Address = 0x110002E4
	 */
	ldr r0, =0x110002E0
	ldr r1, [r0]		//读出GPM4CON的值
	bic r1, r1, #0xf0	//将GPM4CON[4：7]清零
	orr r1, r1, #0x10	//将GPM4_1设置为输出引脚
	str r1, [r0]		//将设置的值写回GPM4CON

	ldr r0, =0x110002E4
	ldr r1, [r0]		//读出GPM4DAT的值
	bic r1, r1, #2		//将CPM4DAT的第[1]位清零，清零就是输出低电平了
	orr r1, r1, #2      //将GPM4DAT的第[1]为设置为1,输出高电平，LED灯熄灭
	str r1, [r0]		//将设置的值写回GPM4DAT

	mov pc, lr			//最后不要忘记这一条，将lr的值写回pc，将程序跳回到执行LED2_OFF之后继续执行
ENDPROC(LED2_OFF)

ENTRY(LED3_OFF)
	/*
	 * GPM4CON Address = 0x110002E0
	 * GPM4DAT Address = 0x110002E4
	 */
	ldr r0, =0x110002E0
	ldr r1, [r0]		//读出GPM4CON的值
	bic r1, r1, #0xf00	//将GPM4CON[8：11]清零
	orr r1, r1, #0x100	//将GPM4_2设置为输出引脚
	str r1, [r0]		//将设置的值写回GPM4CON

	ldr r0, =0x110002E4
	ldr r1, [r0]		//读出GPM4DAT的值
	bic r1, r1, #4		//将CPM4DAT的第[0]位清零，清零就是输出低电平了
	orr r1, r1, #4      //将GPM4DAT的第[0]为设置为1,输出高电平，LED灯熄灭
	str r1, [r0]		//将设置的值写回GPM4DAT

	mov pc, lr			//最后不要忘记这一条，将lr的值写回pc，将程序跳回到执行LED3_OFF之后继续执行
ENDPROC(LED3_OFF)

ENTRY(LED4_OFF)
	/*
	 * GPM4CON Address = 0x110002E0
	 * GPM4DAT Address = 0x110002E4
	 */
	ldr r0, =0x110002E0
	ldr r1, [r0]		//读出GPM4CON的值
	bic r1, r1, #0xf000	//将GPM4CON[0:3]清零
	orr r1, r1, #0x1000	//将GPM4_3设置为输出引脚
	str r1, [r0]		//将设置的值写回GPM4CON

	ldr r0, =0x110002E4
	ldr r1, [r0]		//读出GPM4DAT的值
	bic r1, r1, #8		//将CPM4DAT的第[0]位清零，清零就是输出低电平了
	orr r1, r1, #8      //将GPM4DAT的第[0]为设置为1,输出高电平，LED灯熄灭
	str r1, [r0]		//将设置的值写回GPM4DAT

	mov pc, lr			//最后不要忘记这一条，将lr的值写回pc，将程序跳回到执行LED4_OFF之后继续执行
ENDPROC(LED4_OFF)

ENTRY(DELAY)
	/*
	 * 延时函数
	 */
	ldr r1, =0x000F0000
LOOP:
	sub r1, r1, #0x01
	cmp r1, #0x00
	bne LOOP
	mov pc, lr

ENDPROC(DELAY)
