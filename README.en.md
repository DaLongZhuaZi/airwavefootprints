# Airwave Footprints / 电波足迹

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![HarmonyOS SDK](https://img.shields.io/badge/HarmonyOS_SDK-26.0.0_(API_26)-blue.svg)](https://developer.harmonyos.com/)
[![Language](https://img.shields.io/badge/Language-ArkTS-orange.svg)]()

**🌐 Language / 语言:** English | [中文](README.md)

---

## What this is

Airwave Footprints is a **passive radio-observation tool for HarmonyOS**. It only receives what nearby
devices broadcast on their own, and shows you who is broadcasting, what they call themselves, and what
category they fall into — for field troubleshooting, device self-audit, and study.

Built on NGF (Neon Genesis Framework), which lives in this same repository: `entry/` is the app,
`ngf_framework/` is the framework.

- **Version**: 1.0.0 (versionCode 1000000)
- **Bundle**: `com.dlzz.airwavefootprints`
- **Target**: HarmonyOS 6.0 / API 26

---

## Design commitments

These are not marketing lines — they are constraints actually enforced in the code:

| Commitment | How it is enforced |
|---|---|
| **Receive only, never connect** | Broadcasts are only listened to; no pairing, no injection, no probe frames. All three scan paths (BLE / NearLink / Wi-Fi) are passive. |
| **Strictly offline** | No background network activity at all. The app reaches the network only when you explicitly tap “Update bundled catalog” under Signatures → More. |
| **Data stays on this device** | Observations, watchlist, custom signatures and settings live in the app sandbox. Uninstalling deletes them; we hold no copy. |
| **Only two permissions** | “Device discovery and connection” and “Location”. Location is used only after you enable “record where the phone heard the device”, and never in the background. |

Wi-Fi scanning is granted automatically by the system — nothing for you to do.

---

## Features

### Five tabs

| Tab | Contents |
|---|---|
| **Live** | Radar view plus four list views (strength / timeline / trail / class); pause the display (which is not the same as stopping the scan); open device detail or Hunt. |
| **Filters** | Presets, radio kinds, moving-with-you, new detections, long-stayers, class and fine filters; AND / OR logic; save and delete presets. |
| **Signatures** | Browse, search and edit the signature catalog; create a signature from an observed device; import and export; update the bundled catalog. |
| **Reports** | Named sits, path, sit report, export (including AI export), device comparison, logs. |
| **Settings** | Scan, permissions, radar display, display, location & privacy, notifications & voice, watchlist, data, about. |

### Sub-pages

- **Device detail** — radio facts, vendor and category inference, matched signatures, observation stats and trend, location tag, notes and custom name.
- **Signature editor** — identity / matching / colour / rules / decode fields.
- **Hunt** — single-target tracking with beep and voice feedback.

### First-run onboarding

On first launch the app explains, in order: what it is for → what works without any permission →
why each of the two permissions is needed. **No permission is requested before onboarding completes.**
You can replay it later under Settings → Data.

---

## Permissions

| Permission | Purpose | If declined |
|---|---|---|
| **Device discovery and connection**<br>`ACCESS_BLUETOOTH` + `ACCESS_NEARLINK` | Receives broadcasts from nearby BLE and NearLink devices (earbuds, bands, trackers, beacons…). Broadcast content is read only; no connection is made and no pairing occurs. | The Live tab shows a restricted card; everything else still works. |
| **Location**<br>`APPROXIMATELY_LOCATION` | Used only after you enable “record where the phone heard the device”, to tag observations and draw your own track. Never in the background. | Observations continue, just without a location. |

App-store rules require explaining the purpose *before* requesting, so the explanation lives in the
onboarding and Settings rather than in a bare system dialog.

---

## Bundled signature catalog

- `entry/src/main/resources/rawfile/fieldwatch-signatures-v2.json` — **304 signatures**, `catalogVersion: 89`
- Vendor prefixes (OUI) come from the public IEEE registries, bundled offline
- The catalog ships offline, can be exported for inspection, and can be overridden by your own rules

---

## Project layout

```
entry/src/main/ets/
├── entryability/          EntryAbility (main) + MultitonEntryAbility
├── pages/
│   ├── fieldwatch/        application pages
│   │   ├── FieldwatchPage.ets                five tabs + live radar (the core)
│   │   ├── FieldwatchDeviceDetailPage.ets    device detail
│   │   ├── FieldwatchSignatureEditorPage.ets signature editor
│   │   ├── FieldwatchSignaturesPage.ets      signature catalog
│   │   ├── FieldwatchHuntPage.ets            single-target hunt
│   │   └── FieldwatchOnboardingPage.ets      first-run onboarding
│   └── ngf/               NGF framework showcase and verification pages
└── fieldwatch/
    ├── application/       app state and use-case orchestration
    ├── data/              catalog / observation / settings repositories
    ├── domain/            models, parsing, inference, filtering, candidates, export, vendor DB
    │   └── signatures/    catalog, matching engine, models
    ├── platform/          file gateway, PDF, hunt feedback, watch alerts
    ├── radio/             BLE / NearLink / Wi-Fi scanners and coordinator
    └── ui/                palette, buttons, chips, radar clustering, signal rows
```

---

## Build and run

Open the repository root in DevEco Studio, or use the command line:

```powershell
# point at your own SDK root
$env:DEVECO_SDK_HOME='<DevEco Studio>/sdk'

# debug build
& '<DevEco Studio>/tools/hvigor/bin/hvigorw.bat' assembleHap --no-daemon

# release build
& '<DevEco Studio>/tools/hvigor/bin/hvigorw.bat' assembleHap --mode module -p product=default -p buildMode=release --no-daemon
```

Output: `entry/build/default/outputs/default/entry-default-signed.hap`

> Machine-specific paths and device targets are recorded in `.local-rules/build-commands.local.md`
> and `.local-rules/device-hdc.local.md` — do not copy them into this file.

---

## Tests

```powershell
& '<DevEco Studio>/tools/hvigor/bin/hvigorw.bat' test --no-daemon
```

Tests live in `entry/src/test/` (20 files). The `Fieldwatch*` suites cover domain logic: parsing,
filtering, candidates, signature matching, the vendor database, watch alerts, privacy export,
settings backup, permissions and theming.

> ⚠️ **Important**: `hvigorw test` still prints `BUILD SUCCESSFUL` **even when cases fail**.
> Always assert that the count of `> hvigor ERROR: Error in ` lines is 0, or you will miss failures.

---

## Known limits

- Signal strength, vendor inference, signature matching and device explanations are **inferences drawn
  from broadcast content only**. They do not confirm a device's identity, ownership or intent and must
  not be the sole basis for evidence or decisions.
- The bundled catalog is compiled from public material and has limited coverage; **no match is a normal
  outcome**, not a sign that something is wrong with the device.
- Availability depends on whether the system exposes broadcast content to the app; behaviour may differ
  across devices and OS versions.

---

## Related documents

| Document | Contents |
|---|---|
| [AGENTS.md](AGENTS.md) | Agent working rules for this repo (layering, hard ArkTS rules, delivery flow) |
| [.rules/README.md](.rules/README.md) | Skill-rule index |
| [docs/Fieldwatch功能完整清单.md](docs/Fieldwatch功能完整清单.md) | Feature baseline and acceptance checklist |
| [docs/Fieldwatch鸿蒙能力映射.md](docs/Fieldwatch鸿蒙能力映射.md) | Android → HarmonyOS capability mapping |
| [docs/Fieldwatch鸿蒙验收矩阵.md](docs/Fieldwatch鸿蒙验收矩阵.md) | Acceptance matrix |

---

## License

[MIT](LICENSE)
