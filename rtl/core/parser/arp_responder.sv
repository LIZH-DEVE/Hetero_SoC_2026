`timescale 1ns / 1ps

/**
 * 功能: 静态 ARP 应答器
 * 逻辑: 识别到 ARP Request 且目标 IP 匹配时，构造 ARP Reply。
 */
module arp_responder (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] i_arp_data,
    input  logic        i_arp_valid,
    output logic [31:0] o_tx_data,
    output logic        o_tx_valid
);
    // 简化逻辑：此处作为 Task 8.3 的预留接口
    // 实际开发中会解析 i_arp_data 中的 Target IP
    // 如果匹配本网卡 IP，则拉高 o_tx_valid 发送硬编码的 MAC 地址
    assign o_tx_valid = 0; 
endmodule