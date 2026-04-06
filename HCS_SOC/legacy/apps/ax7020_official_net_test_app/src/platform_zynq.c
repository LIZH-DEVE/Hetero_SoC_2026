/*
 * Copyright (C) 2010 - 2019 Xilinx, Inc.
 * All rights reserved.
 */

#ifdef __arm__

#include "xparameters.h"
#include "xparameters_ps.h"
#include "xil_cache.h"
#include "xscugic.h"
#include "xscutimer.h"
#include "lwip/tcp.h"
#include "xil_printf.h"
#include "platform.h"
#include "platform_config.h"
#include "netif/xadapter.h"

#define INTC_DEVICE_ID      XPAR_SCUGIC_SINGLE_DEVICE_ID
#define TIMER_DEVICE_ID     XPAR_SCUTIMER_DEVICE_ID
#define INTC_BASE_ADDR      XPAR_SCUGIC_0_CPU_BASEADDR
#define INTC_DIST_BASE_ADDR XPAR_SCUGIC_0_DIST_BASEADDR
#define TIMER_IRPT_INTR     XPAR_SCUTIMER_INTR

#define RESET_RX_CNTR_LIMIT 400

void tcp_fasttmr(void);
void tcp_slowtmr(void);

static XScuTimer TimerInstance;
static int ResetRxCntr = 0;

extern struct netif *echo_netif;

volatile int TcpFastTmrFlag = 0;
volatile int TcpSlowTmrFlag = 0;

#if LWIP_DHCP == 1
volatile int dhcp_timoutcntr = 24;
void dhcp_fine_tmr(void);
void dhcp_coarse_tmr(void);
#endif

void timer_callback(XScuTimer *TimerInst)
{
    static int detect_eth_link_status = 0;
    static int odd = 1;
#if LWIP_DHCP == 1
    static int dhcp_timer = 0;
#endif

    detect_eth_link_status++;
    TcpFastTmrFlag = 1;
    odd = !odd;
    ResetRxCntr++;

    if (odd) {
#if LWIP_DHCP == 1
        dhcp_timer++;
        dhcp_timoutcntr--;
#endif
        TcpSlowTmrFlag = 1;
#if LWIP_DHCP == 1
        dhcp_fine_tmr();
        if (dhcp_timer >= 120) {
            dhcp_coarse_tmr();
            dhcp_timer = 0;
        }
#endif
    }

    if (ResetRxCntr >= RESET_RX_CNTR_LIMIT) {
        xemacpsif_resetrx_on_no_rxdata(echo_netif);
        ResetRxCntr = 0;
    }

    if (detect_eth_link_status == ETH_LINK_DETECT_INTERVAL) {
        eth_link_detect(echo_netif);
        detect_eth_link_status = 0;
    }

    XScuTimer_ClearInterruptStatus(TimerInst);
}

void platform_setup_timer(void)
{
    int status;
    XScuTimer_Config *config_ptr;
    int timer_load_value;

    config_ptr = XScuTimer_LookupConfig(TIMER_DEVICE_ID);
    status = XScuTimer_CfgInitialize(&TimerInstance, config_ptr, config_ptr->BaseAddr);
    if (status != XST_SUCCESS) {
        xil_printf("Scutimer Cfg initialization failed\r\n");
        return;
    }

    status = XScuTimer_SelfTest(&TimerInstance);
    if (status != XST_SUCCESS) {
        xil_printf("Scutimer Self test failed\r\n");
        return;
    }

    XScuTimer_EnableAutoReload(&TimerInstance);
    timer_load_value = XPAR_CPU_CORTEXA9_0_CPU_CLK_FREQ_HZ / 8;
    XScuTimer_LoadTimer(&TimerInstance, timer_load_value);
}

void platform_setup_interrupts(void)
{
    Xil_ExceptionInit();
    XScuGic_DeviceInitialize(INTC_DEVICE_ID);
    Xil_ExceptionRegisterHandler(
        XIL_EXCEPTION_ID_IRQ_INT,
        (Xil_ExceptionHandler)XScuGic_DeviceInterruptHandler,
        (void *)INTC_DEVICE_ID);
    XScuGic_RegisterHandler(
        INTC_BASE_ADDR,
        TIMER_IRPT_INTR,
        (Xil_ExceptionHandler)timer_callback,
        (void *)&TimerInstance);
    XScuGic_EnableIntr(INTC_DIST_BASE_ADDR, TIMER_IRPT_INTR);
}

void platform_enable_interrupts(void)
{
    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
    XScuTimer_EnableInterrupt(&TimerInstance);
    XScuTimer_Start(&TimerInstance);
}

void init_platform(void)
{
    platform_setup_timer();
    platform_setup_interrupts();
}

void cleanup_platform(void)
{
    Xil_ICacheDisable();
    Xil_DCacheDisable();
}

#endif
