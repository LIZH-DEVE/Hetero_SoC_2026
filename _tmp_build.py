import vitis
import os

workspace_path = r"D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC"
app_name = "crypto_test_app"

client = vitis.create_client()
client.set_workspace(path=workspace_path)
print(f"Building {app_name}...")
client.build(name=app_name)
print("Build finished.")
