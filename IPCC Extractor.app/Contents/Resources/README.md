# IPCC Extractor GUI

[简体中文](README.zh-CN.md) | **English**

Native macOS GUI for downloading or reusing IPSWs, extracting carrier bundles, generating `.ipcc` files, and organizing the output into clean region-based folders.

## What This App Does

IPCC Extractor is built for users who want a GUI-first workflow instead of manually chaining `ipsw`, AEA decryption, DMG mounting, bundle extraction, and `.ipcc` packing steps.

The app can:

- Detect a connected supported device when possible
- Let you choose between `iPhone` and `Cellular iPad`
- Query the latest stable and beta firmware metadata for the selected device
- Use either a downloaded IPSW or a manually selected local IPSW
- Extract all carrier bundles and generate `.ipcc` packages
- Rename common carrier bundles into more readable names
- Organize outputs by region
- Enable carrier testing before install workflows
- Save a full extraction log into the output folder
- Check whether the system `ipsw` tool is installed, current, or likely outdated

## Why The App Uses System `ipsw`

This project intentionally does **not** hard-bundle the `ipsw` binary into the app.

Instead, the app calls the system-installed `ipsw` from Homebrew or your PATH. That keeps updates cleaner:

- the GUI can evolve independently
- the `ipsw` binary can be upgraded separately
- the app bundle stays smaller and easier to maintain

## Requirements

- macOS
- `ipsw` available on the system
- Homebrew recommended for installing or updating `ipsw`
- Enough free disk space for IPSW extraction and temporary files

If `ipsw` is missing, the app shows an alert and offers to install or upgrade it.

## IPSW Status Indicator

The GUI shows a small color indicator in the `ipsw` section:

- Green: `ipsw` is installed and Homebrew does not report it as outdated
- Yellow: `ipsw` is installed but Homebrew reports an available update
- Red: `ipsw` was not found on the system
- Gray: status is still being checked or could not be determined

## Firmware Lookup

The app can look up:

- Latest stable release
- Latest beta release
- A specific version number
- A specific build number

For local IPSWs, you can skip downloading entirely and point the app at an existing `.ipsw` file.

## Supported Device Entry

The GUI is optimized around currently relevant baseband-capable Apple devices:

- `iPhone`
- `Cellular iPad`

You only enter the model suffix, such as:

- `18,2`
- `17,2`

The app combines that with the selected family to form device identifiers such as:

- `iPhone18,2`
- `iPad17,2`

## Output Layout

By default, the app creates an `IPCC_Extractor` folder next to the `.app` bundle.

You can also choose a custom output folder from inside the app.

Generated IPCC files are organized into region folders such as:

- `Mainland_China`
- `Hong_Kong`
- `Taiwan`
- `Japan`
- `Korea`
- `USA`
- `Canada`
- `Australia_NZ`
- `UK_Ireland`
- `Europe`
- `Other`

The app also writes a timestamped log file into the selected output folder:

- `ipcc_extractor_YYYY-MM-DD_HH-mm-ss.log`

## Repository Structure

This repository is intentionally focused on the GUI build and its single extraction backend:

- `IPCC Extractor.app`
- `IPCCExtractorApp.swift`
- `extract_all_ipcc.sh`

Older wrapper scripts are not required for the GUI build and are intentionally excluded from the current repo layout.

## Build

Example local build flow:

```bash
swiftc -parse-as-library IPCCExtractorApp.swift -o IPCC\ Extractor.app/Contents/MacOS/launcher
codesign --force --deep --sign - IPCC\ Extractor.app
```

You should also copy the latest `extract_all_ipcc.sh` into:

```text
IPCC Extractor.app/Contents/Resources/extract_all_ipcc.sh
```

## Typical Workflow

1. Launch `IPCC Extractor.app`.
2. Confirm the app sees your system `ipsw`.
3. Choose `iPhone` or `Cellular iPad`.
4. Enter the model suffix.
5. Either choose a local IPSW or pick a download mode.
6. Choose the output folder if you do not want the default location.
7. Start extraction.
8. Wait for region-organized `.ipcc` output and review the saved log if needed.

## Installing IPCC On iPhone

1. Connect the iPhone to your Mac.
2. Unlock the device and trust the computer.
3. Open Finder and select the device in the sidebar.
4. Stay on the `General` page.
5. Hold `Option`.
6. Click `Check for Update...`
7. Choose the target `.ipcc` file from the app output folder.

## Troubleshooting

If latest build lookup is empty:

- confirm the device identifier is correct
- confirm `ipsw` is installed and runnable
- check network access
- review the saved log file in the output folder

If `ipsw` status looks wrong:

- run `brew outdated ipsw --json=v2`
- confirm Homebrew can see the installed formula

If extraction fails:

- make sure the selected output volume has enough free space
- try using a local IPSW instead of downloading again
- inspect the log file written by the app
