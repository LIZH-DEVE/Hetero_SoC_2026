/*
 * Based on the AX7020 official lwIP net_test example.
 */

#include <stdio.h>

#ifndef UDP_GATEWAY_SMOKE_ONLY_BUILD
#define UDP_GATEWAY_SMOKE_ONLY_BUILD 0
#endif

#include "xparameters.h"
#include "xil_printf.h"
#include "xstatus.h"

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
#include "netif/xadapter.h"
#include "platform.h"
#include "platform_config.h"
#include "xil_cache.h"

#include "lwip/pbuf.h"
#include "lwip/netif.h"
#include "lwip/tcp.h"
#else
#include "xil_cache.h"
#include "xuartps.h"
#endif

#include "udp_crypto_gateway.h"

#if UDP_GATEWAY_SMOKE_ONLY_BUILD
static XUartPs g_smoke_uart;

static int smoke_uart1_init_115200(void)
{
    XUartPs_Config *config;
    int status;

    config = XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
    if (config == NULL) {
        return XST_FAILURE;
    }

    status = XUartPs_CfgInitialize(&g_smoke_uart, config, config->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XUartPs_SetBaudRate(&g_smoke_uart, 115200U);
    if (status != XST_SUCCESS) {
        return status;
    }

    return XST_SUCCESS;
}
#endif

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
void lwip_init(void);
void tcp_fasttmr(void);
void tcp_slowtmr(void);

extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;

static struct netif server_netif;
struct netif *echo_netif;

#define UDP_GATEWAY_USE_CUSTOM_PL_PREP 0
#ifndef UDP_GATEWAY_DIRECT_MMIO_SMOKE_CASE
#define UDP_GATEWAY_DIRECT_MMIO_SMOKE_CASE 0U
#endif

static netif_input_fn g_original_netif_input;
static unsigned long g_input_wrap_packets;

static err_t debug_netif_input(struct pbuf *p, struct netif *inp)
{
    unsigned char hdr[64];
    u16_t copied;
    u16_t ethertype;
    err_t err;

    g_input_wrap_packets++;
    copied = pbuf_copy_partial(p, hdr, (u16_t)((sizeof(hdr) < p->tot_len) ? sizeof(hdr) : p->tot_len), 0U);
    if (copied >= 14U) {
        ethertype = (u16_t)(((u16_t)hdr[12] << 8) | (u16_t)hdr[13]);
        if (ethertype == 0x0806U) {
            xil_printf("main: netif_input pkt=%lu type=ARP len=%u\r\n",
                       g_input_wrap_packets,
                       (unsigned)p->tot_len);
        } else if (ethertype == 0x0800U && copied >= 34U) {
            unsigned ip_proto = hdr[23];
            unsigned ihl_bytes = (unsigned)(hdr[14] & 0x0FU) * 4U;
            unsigned src_ip_off = 26U;
            unsigned dst_ip_off = 30U;

            if (ip_proto == 17U && copied >= (u16_t)(14U + ihl_bytes + 8U)) {
                unsigned udp_off = 14U + ihl_bytes;
                unsigned dst_port = ((unsigned)hdr[udp_off + 2] << 8) | (unsigned)hdr[udp_off + 3];
                if ((dst_port == 4660U) || (dst_port == 4661U)) {
                    xil_printf("main: netif_input pkt=%lu type=IPv4/UDP dst_port=%u src=%u.%u.%u.%u dst=%u.%u.%u.%u len=%u\r\n",
                               g_input_wrap_packets,
                               dst_port,
                               hdr[src_ip_off], hdr[src_ip_off + 1], hdr[src_ip_off + 2], hdr[src_ip_off + 3],
                               hdr[dst_ip_off], hdr[dst_ip_off + 1], hdr[dst_ip_off + 2], hdr[dst_ip_off + 3],
                               (unsigned)p->tot_len);
                }
            } else {
                if (ip_proto == 1U) {
                    xil_printf("main: netif_input pkt=%lu type=IPv4 proto=%u len=%u\r\n",
                               g_input_wrap_packets,
                               ip_proto,
                               (unsigned)p->tot_len);
                }
            }
        } else if (g_input_wrap_packets <= 8U) {
            xil_printf("main: netif_input pkt=%lu type=0x%04X len=%u\r\n",
                       g_input_wrap_packets,
                       ethertype,
                       (unsigned)p->tot_len);
        }
    } else {
        xil_printf("main: netif_input pkt=%lu short len=%u copied=%u\r\n",
                   g_input_wrap_packets,
                   (unsigned)p->tot_len,
                   (unsigned)copied);
    }

    err = g_original_netif_input(p, inp);
    if (err != ERR_OK) {
        xil_printf("main: netif_input dispatch err=%d pkt=%lu\r\n", (int)err, g_input_wrap_packets);
    }
    return err;
}

static void print_ip(char *msg, ip_addr_t *ip)
{
    print(msg);
    xil_printf("%d.%d.%d.%d\n\r", ip4_addr1(ip), ip4_addr2(ip), ip4_addr3(ip), ip4_addr4(ip));
}

static void print_ip_settings(ip_addr_t *ip, ip_addr_t *mask, ip_addr_t *gw)
{
    print_ip("Board IP: ", ip);
    print_ip("Netmask : ", mask);
    print_ip("Gateway : ", gw);
}
#endif

int main(void)
{
#if UDP_GATEWAY_SMOKE_ONLY_BUILD
    if (smoke_uart1_init_115200() != XST_SUCCESS) {
        for (;;) {
        }
    }

    Xil_ICacheDisable();
    Xil_DCacheDisable();
    print_app_header();
    xil_printf("main: backup-XSA smoke-only build enabled\r\n");
    xil_printf("main: direct MMIO smoke mode enabled case=%u\r\n",
               (unsigned)UDP_GATEWAY_DIRECT_MMIO_SMOKE_CASE);
    udp_crypto_gateway_run_direct_smoke(UDP_GATEWAY_DIRECT_MMIO_SMOKE_CASE);
    while (1) {
    }
#else
    ip_addr_t ipaddr, netmask, gw;
    unsigned char mac_ethernet_address[] = { 0x02, 0x0a, 0x35, 0x00, 0x01, 0x20 };
    static unsigned long rx_batches = 0U;
    static unsigned long rx_packets_total = 0U;

    echo_netif = &server_netif;

    init_platform();
#if UDP_GATEWAY_USE_CUSTOM_PL_PREP
    udp_crypto_gateway_early_platform_prepare();
    udp_crypto_gateway_fix_uart_after_platform_init();
#endif

    IP4_ADDR(&ipaddr, 192, 168, 1, 20);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gw, 192, 168, 1, 1);

    print_app_header();
#if !UDP_GATEWAY_USE_CUSTOM_PL_PREP
    xil_printf("main: custom PL clock/reset prep skipped for design1 route\r\n");
#endif
#if UDP_GATEWAY_DIRECT_MMIO_SMOKE_CASE != 0
    xil_printf("main: direct MMIO smoke mode enabled case=%u\r\n",
               (unsigned)UDP_GATEWAY_DIRECT_MMIO_SMOKE_CASE);
    udp_crypto_gateway_run_direct_smoke(UDP_GATEWAY_DIRECT_MMIO_SMOKE_CASE);
    while (1) {
    }
#endif
    lwip_init();

    if (!xemac_add(echo_netif, &ipaddr, &netmask, &gw, mac_ethernet_address, PLATFORM_EMAC_BASEADDR)) {
        xil_printf("Error adding N/W interface\n\r");
        return -1;
    }

    g_original_netif_input = echo_netif->input;
    echo_netif->input = debug_netif_input;
    xil_printf("main: netif->input wrapped flags=0x%02x input=0x%08lx\r\n",
               (unsigned)echo_netif->flags,
               (unsigned long)g_original_netif_input);

    netif_set_default(echo_netif);
    platform_enable_interrupts();
    netif_set_up(echo_netif);

    print_ip_settings(&ipaddr, &netmask, &gw);

    if (start_application() != 0) {
        xil_printf("Failed to start UDP crypto gateway\r\n");
        return -2;
    }

    while (1) {
        if (TcpFastTmrFlag) {
            tcp_fasttmr();
            TcpFastTmrFlag = 0;
        }
        if (TcpSlowTmrFlag) {
            tcp_slowtmr();
            TcpSlowTmrFlag = 0;
        }
        {
            int rx_packets = xemacif_input(echo_netif);
            if (rx_packets > 0) {
                rx_batches++;
                rx_packets_total += (unsigned long)rx_packets;
                xil_printf("main: xemacif_input rx_packets=%d batches=%lu total=%lu\r\n",
                           rx_packets,
                           rx_batches,
                           rx_packets_total);
            }
        }
        transfer_data();
    }

    cleanup_platform();
    return 0;
#endif
}
