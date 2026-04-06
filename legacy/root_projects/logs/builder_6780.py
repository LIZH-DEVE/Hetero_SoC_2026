# 2026-01-27T13:02:53.548834500
import vitis

client = vitis.create_client()
client.set_workspace(path="D:/FPGAhanjia/Hetero_SoC_2026")

platform = client.create_platform_component(name = "dma_hw_platform",hw_design = "D:/FPGAhanjia/Hetero_SoC_2026/HCS_SOC/system_wrapper.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0")

comp = client.create_app_component(name="crypto_test_app",platform = "D:/FPGAhanjia/Hetero_SoC_2026/dma_hw_platform/export/dma_hw_platform/dma_hw_platform.xpfm",domain = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="dma_hw_platform")
status = platform.build()

comp = client.get_component(name="crypto_test_app")
comp.build()

vitis.dispose()

