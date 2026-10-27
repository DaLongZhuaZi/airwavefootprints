import json
import os
from pathlib import Path

from hypium.action.device.uidriver import UiDriver
from hypium.uidriver.by import BY


HDC_DIR = r"G:\DevEco Studio 26\DevEco Studio\sdk\default\openharmony\toolchains"
PACKAGE = "com.dlzz.airwavefootprints"
DEVICE = "192.168.5.133:42355"
OUT = Path("tmp/hypium-backup-roundtrip")
OUT.mkdir(parents=True, exist_ok=True)
os.environ["PATH"] = HDC_DIR + os.pathsep + os.environ.get("PATH", "")

driver = UiDriver.connect(device_sn=DEVICE, report_path=str(OUT / "hypium-report"), log_level="info")
result = {"device": driver.device_sn, "closed": False, "actions": []}
try:
    driver.wait_for_idle(idle_time=0.2, timeout=10)
    result["window"] = str(driver.get_current_window())
    result["actions"].append("current_window_observed")
    driver.touch((0.076, 0.639), wait_time=1)
    driver.wait_for_idle(idle_time=0.2, timeout=10)
    result["actions"].append("open_settings_from_live_tab")
    result["screenshots"] = [driver.capture_screen(str(OUT / "backup-before.jpeg"))]
    result["screenshots"].append(driver.capture_screen(str(OUT / "settings-top.jpeg")))
    buttons = driver.find_all_components(BY.type("Button")) or []
    result["buttons"] = [
        {
            "text": button.getText(),
            "text_ascii": ascii(button.getText()),
            "enabled": button.isEnabled(),
            "clickable": button.isClickable(),
            "bounds": str(button.getBounds()),
        }
        for button in buttons
    ]
    result["screenshots"].append(driver.capture_screen(str(OUT / "buttons.jpeg")))
finally:
    driver.close()
    result["closed"] = True
    (OUT / "driver-probe-result.json").write_text(json.dumps(result, ensure_ascii=True, indent=2), encoding="utf-8")
print(json.dumps(result, ensure_ascii=True, indent=2))
