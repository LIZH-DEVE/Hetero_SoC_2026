setws D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tmp/vitis_2023_probe_ws_2
platform create -name ax7020_probe_platform -hw D:/FPGAhanjia/Hetero_SoC_2026_3/AX7020_2023.1/course_s2_vitis/06_net_test/Vitis/design_1_wrapper/hw/design_1_wrapper.xsa -proc ps7_cortexa9_0 -os standalone -out D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tmp/vitis_2023_probe_ws_2
platform generate
app create -name sanity_app -platform ax7020_probe_platform -domain standalone_domain -template {Hello World}
app list
exit
