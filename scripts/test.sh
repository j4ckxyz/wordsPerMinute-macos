#!/bin/zsh
# Runs the WPMCore unit tests (Swift Testing).
# With only the Command Line Tools installed, Testing.framework lives outside the
# default search paths, so point the compiler/linker at it. With Xcode it's found automatically.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
FW=""
for d in "$DEV/Library/Developer/Frameworks" "$DEV/Platforms/MacOSX.platform/Developer/Library/Frameworks"; do
  [[ -d "$d/Testing.framework" ]] && FW="$d" && break
done
if [[ -n "$FW" ]]; then
  exec swift test -Xswiftc -F -Xswiftc "$FW" -Xlinker -F -Xlinker "$FW" -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$FW/../usr/lib" "$@"
else
  exec swift test "$@"
fi
