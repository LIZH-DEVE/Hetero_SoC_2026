`timescale 1ns / 1ps

/**
 * Package: pkg_axi_stream
 * Task 1.1: 协议立法与总线基座
 */
package pkg_axi_stream;

    // =========================================================================
    // Task 1.1: 协议长度与头部定义 (Protocol Lengths & Headers)
    // =========================================================================
    // 核心定义：IP/UDP 头部长度与 Payload 计算
    parameter ETH_HEADER_LEN    = 14; 
    parameter IP_HEADER_MIN_LEN = 20; 
    parameter UDP_HEADER_LEN    = 8; 

    // 长度校验阈值
    parameter MAX_FRAME_LEN     = 1518; // 标准以太网最大帧长 

    // =========================================================================
    // Task 1.1: 对齐与 AXI 约束 (Alignment & AXI Constraints)
    // =========================================================================
    // AXI 约束：MAX_BURST_LEN = 256 (AXI4 Limit)
    parameter AXI_BURST_LIMIT   = 256; 

    // 对齐约束：Descriptor/Buffer 地址必须 64-Byte Aligned
    parameter ALIGN_MASK_64B    = 6'h3F; 
    
    // Payload 对齐：16-Byte Aligned (128-bit)
    parameter ALIGN_MASK_16B    = 4'hF; 

    // =========================================================================
    // 错误码定义 (Error Codes)
    // =========================================================================
    typedef enum logic [3:0] {
        ERR_NONE        = 4'h0, // 正常
        ERR_BAD_ALIGN   = 4'h1, // Payload 长度不对齐 
        ERR_MALFORMED   = 4'h2, // 包格式错误 (udp_len > ip_len) 
        ERR_AXI_SLVERR  = 4'h3, // AXI 总线从机错误
        ERR_AXI_DECERR  = 4'h4, // AXI 总线解码错误
        ERR_ACL_DROP    = 4'h5  // 命中且指纹匹配 -> Drop
    } err_code_t;

endpackage