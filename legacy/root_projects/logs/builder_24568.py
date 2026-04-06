# 2026-01-28T10:01:21.420200
import vitis

client = vitis.create_client()
client.set_workspace(path="D:/FPGAhanjia/Hetero_SoC_2026")

platform = client.get_component(name="dma_hw_platform")
status = platform.update_hw(hw_design = "D:/FPGAhanjia/Hetero_SoC_2026/HCS_SOC/dma_sys_wrapper_day07.xsa")

status = platform.build()

status = platform.build()

comp = client.get_component(name="crypto_test_app")
comp.build()

vitis.dispose()

