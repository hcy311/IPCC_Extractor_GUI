#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
LANG_MODE=zh exec "$DIR/extract_all_ipcc.sh" "$@"
