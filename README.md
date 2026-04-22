# IPCC Extractor GUI

macOS GUI tool for downloading IPSWs, extracting carrier bundles, generating IPCC files, and organizing them by region.

## Features

- Native macOS window UI
- Auto-detect connected iPhone model when possible
- Query latest stable and beta builds
- Manually choose a local IPSW file
- Generate and organize IPCC files by region
- Enable carrier testing automatically
- Install or update `ipsw` from inside the app
- Uses the system-installed `ipsw` tool instead of bundling it into the app

## Regions

- Mainland_China
- Hong_Kong
- Taiwan
- Japan
- Korea
- USA
- Canada
- Australia_NZ
- UK_Ireland
- Europe
- Other

## Files

- `IPCC Extractor.app`: macOS app bundle
- `IPCCExtractorApp.swift`: SwiftUI source
- `extract_all_ipcc.sh`: core extraction script
- `extract_all_ipcc_zh.sh`: Chinese wrapper
- `extract_all_ipcc_en.sh`: English wrapper
