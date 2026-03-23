#ifndef UDP_CRYPTO_GATEWAY_H
#define UDP_CRYPTO_GATEWAY_H

void udp_crypto_gateway_early_platform_prepare(void);
void udp_crypto_gateway_fix_uart_after_platform_init(void);
void print_app_header(void);
void udp_crypto_gateway_run_direct_smoke(unsigned case_id);
int start_application(void);
int transfer_data(void);

#endif
