#!/bin/sh

set -eu

cd "$(git rev-parse --show-toplevel)"

failed=0

check_absent() {
  description=$1
  pattern=$2
  shift 2

  if rg -n "$pattern" "$@"; then
    printf '\nCtrlX brand check failed: %s\n' "$description" >&2
    failed=1
  fi
}

check_absent \
  "the website still presents the old product name" \
  '(title|description|heroTitle|lede|alt)=["{][^\n]*(Gallager|ClaudeSpy)' \
  website/src

check_absent \
  "production UI still presents the old product name" \
  '(Text|Label|Button|navigationTitle|windowTitle|defaultTitle)\("(Gallager|ClaudeSpy)"' \
  Ctrlx CtrlxServer CtrlxPackage/Sources/CtrlxFeature \
  CtrlxPackage/Sources/CtrlxServerFeature/Views

if [ "$failed" -ne 0 ]; then
  exit 1
fi

printf 'CtrlX brand boundary check passed.\n'
