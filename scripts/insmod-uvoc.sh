#!/bin/sh
# Load gpu_uvoc_mt6789.ko. Plain mode only patches the working table.
# Full mode mirrors GED and signed tables for the verified target layout.
# Usage (as root): FULL_SYNC=1 sh scripts/insmod-uvoc.sh [path/to/gpu_uvoc_mt6789.ko]
set -eu
KO=${1:-src/gpu_uvoc_mt6789.ko}
FULL_SYNC=${FULL_SYNC:-0}
SYNC_TARGET=5313106
GED_BSS_SIZE=102980
MTK_BSS_SIZE=1488
EXPECTED_GED_SCM=${EXPECTED_GED_SCM:-g1cfd966d634d-dirty}
EXPECTED_MTK_SCM=${EXPECTED_MTK_SCM:-g1cfd966d634d-dirty}
EXPECTED_GED_CORE=${EXPECTED_GED_CORE:-352256}
EXPECTED_MTK_CORE=${EXPECTED_MTK_CORE:-114688}
[ -f "$KO" ] || { echo "missing: $KO"; exit 1; }
case "$FULL_SYNC" in
  0|1) ;;
  *) echo "FULL_SYNC must be 0 or 1"; exit 1 ;;
esac

if [ "$FULL_SYNC" = 1 ]; then
  GED_SCM=$(cat /sys/module/ged/scmversion 2>/dev/null || true)
  MTK_SCM=$(cat /sys/module/mtk_gpufreq_mt6789/scmversion 2>/dev/null || true)
  GED_CORE=$(cat /sys/module/ged/coresize 2>/dev/null || true)
  MTK_CORE=$(cat /sys/module/mtk_gpufreq_mt6789/coresize 2>/dev/null || true)
  [ "$GED_SCM" = "$EXPECTED_GED_SCM" ] || {
    echo "refusing full sync: ged scm=$GED_SCM, expected=$EXPECTED_GED_SCM"; exit 1;
  }
  [ "$MTK_SCM" = "$EXPECTED_MTK_SCM" ] || {
    echo "refusing full sync: mtk_gpufreq_mt6789 scm=$MTK_SCM, expected=$EXPECTED_MTK_SCM"; exit 1;
  }
  [ "$GED_CORE" = "$EXPECTED_GED_CORE" ] || {
    echo "refusing full sync: ged core size=$GED_CORE, expected=$EXPECTED_GED_CORE"; exit 1;
  }
  [ "$MTK_CORE" = "$EXPECTED_MTK_CORE" ] || {
    echo "refusing full sync: mtk_gpufreq_mt6789 core size=$MTK_CORE, expected=$EXPECTED_MTK_CORE"; exit 1;
  }

  KPTR=$(cat /proc/sys/kernel/kptr_restrict)
  echo 0 > /proc/sys/kernel/kptr_restrict
  trap 'echo "$KPTR" > /proc/sys/kernel/kptr_restrict' EXIT

  GB=$(cat /sys/module/ged/sections/.bss 2>/dev/null || true)
  MB=$(cat /sys/module/mtk_gpufreq_mt6789/sections/.bss 2>/dev/null || true)
  case "$GB" in
    0x0|0x0000000000000000) echo "GED BSS still hidden"; exit 1 ;;
    0x*[0-9a-fA-F]) ;;
    *) echo "invalid GED BSS address: $GB"; exit 1 ;;
  esac
  case "$MB" in
    0x0|0x0000000000000000) echo "mtk_gpufreq_mt6789 BSS still hidden"; exit 1 ;;
    0x*[0-9a-fA-F]) ;;
    *) echo "invalid mtk_gpufreq_mt6789 BSS address: $MB"; exit 1 ;;
  esac
  echo "GED=$GB MTK=$MB"
fi

dmesg -c > /dev/null 2>&1 || true
if [ "$FULL_SYNC" = 1 ]; then
  insmod "$KO" sync_target="$SYNC_TARGET" ged_bss="$GB" ged_bss_size="$GED_BSS_SIZE" \
    mt6789_bss="$MB" mt6789_bss_size="$MTK_BSS_SIZE"
else
  insmod "$KO"
fi
LOG=$(dmesg -c 2>/dev/null || true)
printf '%s\n' "$LOG" | grep gpu-uvoc || true
if [ "$FULL_SYNC" = 1 ]; then
  printf '%s\n' "$LOG" | grep -q "GED tables synced" || {
    echo "full sync incomplete: GED table was not synced"; exit 1;
  }
  printf '%s\n' "$LOG" | grep -q "signed table synced" || {
    echo "full sync incomplete: signed table was not synced"; exit 1;
  }
fi
