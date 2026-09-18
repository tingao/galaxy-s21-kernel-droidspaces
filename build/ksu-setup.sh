#!/bin/bash
# Wire KernelSU-Next (branch: legacy) into the kernel tree.
set -uo pipefail
KROOT=/root/kernel-S21-rewrite
KSU=/root/KernelSU-Next
cd "$KROOT"
echo "=== KernelSU-Next source: $KSU ($(cd $KSU && git log --oneline -1)) ==="
ln -sfn "$KSU/kernel" drivers/kernelsu
ls -l drivers/kernelsu
grep -q "kernelsu" drivers/Makefile || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
python3 - <<'EOF'
p = "drivers/Kconfig"
s = open(p, encoding="utf-8").read()
if "drivers/kernelsu/Kconfig" not in s:
    i = s.rfind("\nendmenu")
    assert i > 0, "no trailing endmenu in drivers/Kconfig"
    s = s[:i] + '\nsource "drivers/kernelsu/Kconfig"\n' + s[i+1:]
    open(p, "w", encoding="utf-8").write(s)
    print("  drivers/Kconfig: added kernelsu Kconfig source")
else:
    print("  drivers/Kconfig: already wired")
EOF
tail -4 drivers/Makefile
