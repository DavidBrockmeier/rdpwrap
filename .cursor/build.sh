#!/usr/bin/env bash
# Cross-build the Visual C++ RDP Wrapper library with MinGW-w64 and run the
# configuration parser against res/rdpwrap.ini under Wine.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="$ROOT/.cursor/mingw"
SRC="$ROOT/src-x86-x64-Fusix"
WORK="$ROOT/.cursor/out"
mkdir -p "$WORK/src"

for source in stdafx.cpp stdafx.h targetver.h IniFile.cpp IniFile.h dllmain.cpp RDPWrap.cpp; do
  sed -E 's/\[length_is\([^]]*\)\][[:space:]]*//g' "$SRC/$source" > "$WORK/src/$source"
done

# -w: this tree is MSVC source. MinGW's -fpermissive build is expected to
# warn about pointer conversions the Visual C++ compiler accepts.
CXXFLAGS=(-std=c++14 -O2 -w -I"$WORK/src" -I"$SHIM" -DUNICODE -D_UNICODE -fms-extensions -fpermissive)
SOURCES=(stdafx.cpp IniFile.cpp dllmain.cpp RDPWrap.cpp)

symbol() {
  local nm="$1"
  local object="$2"
  local name="$3"
  "$nm" "$object" | awk -v name="$name" '
    $2 == "T" && index($3, name) {
      print $3
      exit
    }
  '
}

def_name() {
  local symbol_name="$1"
  # i686 objects carry the PE underscore prefix. The module-definition
  # internal name omits that prefix; x64 names are already unprefixed.
  if [[ "$symbol_name" == __Z* ]]; then
    printf '%s\n' "${symbol_name#_}"
  else
    printf '%s\n' "$symbol_name"
  fi
}

build_dll() {
  local cxx="$1"
  local label="$2"
  local prefix="${cxx%-g++}"
  local nm="${prefix}-nm"
  local objdump="${prefix}-objdump"
  local object="$WORK/RDPWrap-${label}.o"
  local def="$WORK/exports-${label}.def"
  local dll="$WORK/rdpwrap-${label}.dll"

  "$cxx" "${CXXFLAGS[@]}" -c "$WORK/src/RDPWrap.cpp" -o "$object" 2>"$WORK/compile-${label}.log" \
    || { cat "$WORK/compile-${label}.log" >&2; exit 1; }
  local service_main push_globals
  service_main="$(symbol "$nm" "$object" "ServiceMain")"
  push_globals="$(symbol "$nm" "$object" "SvchostPushServiceGlobals")"
  if [[ -z "$service_main" || -z "$push_globals" ]]; then
    echo "could not find export symbols in $object" >&2
    exit 1
  fi
  cat > "$def" << EOF
EXPORTS
    ServiceMain=$(def_name "$service_main")
    SvchostPushServiceGlobals=$(def_name "$push_globals")
EOF
  "$cxx" "${CXXFLAGS[@]}" -shared -static -o "$dll" \
    "${SOURCES[@]/#/$WORK/src/}" "$def" -lkernel32 2>>"$WORK/compile-${label}.log" \
    || { cat "$WORK/compile-${label}.log" >&2; exit 1; }
  local exports
  exports="$("$objdump" -p "$dll")"
  if ! grep -q 'ServiceMain' <<< "$exports" || ! grep -q 'SvchostPushServiceGlobals' <<< "$exports"; then
    echo "$dll is missing the expected exports" >&2
    exit 1
  fi
  echo "built $dll ($(wc -c < "$dll") bytes) exports ServiceMain, SvchostPushServiceGlobals"
}

build_dll x86_64-w64-mingw32-g++ x64
build_dll i686-w64-mingw32-g++ x86

x86_64-w64-mingw32-g++ "${CXXFLAGS[@]}" -static -mconsole \
  -o "$WORK/ini-check.exe" "$ROOT/.cursor/ini-check.cpp" "$WORK/src/IniFile.cpp" "$WORK/src/stdafx.cpp" \
  -lkernel32 2>"$WORK/compile-ini-check.log" \
  || { cat "$WORK/compile-ini-check.log" >&2; exit 1; }
echo "built $WORK/ini-check.exe"

cp "$ROOT/res/rdpwrap.ini" "$WORK/rdpwrap.ini"
export WINEDEBUG=-all
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
wineboot -u >/dev/null 2>&1 || true
(
  cd "$WORK"
  wine ./ini-check.exe rdpwrap.ini
)

python3 "$ROOT/.cursor/check-ini.py" \
  "$ROOT/res/rdpwrap.ini" \
  "$ROOT/res/rdpwrap-arm-kb.ini"
