/*
 * Phase C shadow-mirror app.
 * Live ports stay on the PS direct backend. Shadow capture runs via PS mirror.
 */

#include <stdio.h>

#include "xparameters.h"
#include "xil_printf.h"

#include "netif/xadapter.h"
#include "platform.h"
#include "platform_config.h"

#include "lwip/pbuf.h"
#include "lwip/netif.h"
#include "lwip/tcp.h"

#include "udp_crypto_gateway.h"

void lwip_init(void);
void tcp_fasttmr(void);
void tcp_slowtmr(void);

extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;

static struct netif server_netif;
struct netif *echo_netif;

static netif_input_fn g_original_netif_input;
static uint32_t g_input_wrap_packets;

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
        if (ethertype == 0x0800U && copied >= 34U) {
            unsigned ip_proto = hdr[23];
            unsigned ihl_bytes = (unsigned)(hdr[14] & 0x0FU) * 4U;

            if (ip_proto == 17U && copied >= (u16_t)(14U + ihl_bytes + 8U)) {
                unsigned udp_off = 14U + ihl_bytes;
                unsigned dst_port = ((unsigned)hdr[udp_off + 2] << 8) | (unsigned)hdr[udp_off + 3];
                if ((dst_port == 4660U) || (dst_port == 4661U) || (dst_port == 4662U)) {
                    xil_printf("shadow-main: netif_input pkt=%u dst_port=%u len=%u\r\n",
                               (unsigned)g_input_wrap_packets,
                               dst_port,
                               (unsigned)p->tot_len);
                }
            }
        }
    }

    err = g_original_netif_input(p, inp);
    if (err != ERR_OK) {
        xil_printf("shadow-main: netif_input err=%d pkt=%u\r\n", (int)err, (unsigned)g_input_wrap_packets);
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

int main(void)
{
    ip_addr_t ipaddr, netmask, gw;
    unsigned char mac_ethernet_address[] = { 0x02, 0x0a, 0x35, 0x00, 0x01, 0x20 };
    static uint32_t rx_batches = 0U;
    static uint32_t rx_packets_total = 0U;

    echo_netif = &server_netif;

    init_platform();

    IP4_ADDR(&ipaddr, 192, 168, 1, 20);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gw, 192, 168, 1, 1);

    xil_printf("UDP gateway shadow mirror image\r\n");
    print_app_header();
    lwip_init();

    if (!xemac_add(echo_netif, &ipaddr, &netmask, &gw, mac_ethernet_address, PLATFORM_EMAC_BASEADDR)) {
        xil_printf("Error adding N/W interface\r\n");
        return -1;
    }

    g_original_netif_input = echo_netif->input;
    echo_netif->input = debug_netif_input;
    xil_printf("shadow-main: netif wrapped flags=0x%02x input=0x%08x\r\n",
               (unsigned)echo_netif->flags,
               (unsigned)(uintptr_t)g_original_netif_input);

    netif_set_default(echo_netif);
    platform_enable_interrupts();
    netif_set_up(echo_netif);

    print_ip_settings(&ipaddr, &netmask, &gw);

    if (start_application() != 0) {
        xil_printf("Failed to start UDP gateway shadow mirror\r\n");
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
                rx_packets_total += (uint32_t)rx_packets;
                xil_printf("shadow-main: xemacif_input rx_packets=%d batches=%u total=%u\r\n",
                           rx_packets,
                           (unsigned)rx_batches,
                           (unsigned)rx_packets_total);
            }
        }
        transfer_data();
    }
}
