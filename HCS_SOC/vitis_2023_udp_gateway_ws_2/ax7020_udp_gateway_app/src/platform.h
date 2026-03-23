/*
 * Copyright (C) 2009 - 2019 Xilinx, Inc.
 * All rights reserved.
 */

#ifndef __PLATFORM_H_
#define __PLATFORM_H_

/* 250 ms tick -> 4 ticks ~= 1 second */
#define ETH_LINK_DETECT_INTERVAL 4

void init_platform(void);
void cleanup_platform(void);
void platform_setup_timer(void);
void platform_enable_interrupts(void);

#endif
