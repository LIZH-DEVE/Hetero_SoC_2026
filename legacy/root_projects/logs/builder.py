# 2026-02-14T01:25:33.349231800
import vitis

client = vitis.create_client()
client.set_workspace(path="D:/FPGAhanjia/Hetero_SoC_2026")

platform = client.create_platform_component(name = "crypto_hw_platform",hw_design = "D:/FPGAhanjia/Hetero_SoC_2026/HCS_SOC/system_wrapper.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="crypto_hw_platform")
status = platform.build()

comp = client.create_app_component(name="crypto_perf_test",platform = "D:/FPGAhanjia/Hetero_SoC_2026/crypto_hw_platform/export/crypto_hw_platform/crypto_hw_platform.xpfm",domain = "standalone_ps7_cortexa9_0")

status = platform.build()

comp = client.get_component(name="crypto_perf_test")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

