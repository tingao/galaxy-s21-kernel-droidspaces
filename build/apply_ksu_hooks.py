#!/usr/bin/env python3
# KernelSU-Next manual hooks for o1q 5.4 (adapted from the official non-GKI doc
# and ravindu644's "scope-minimized manual hooks v1.4"), matched to the exact
# symbol signatures present in KernelSU-Next branch "legacy".
import os, sys
K = "/root/kernel-S21-rewrite"

def rd(p): return open(os.path.join(K, p), encoding="utf-8").read()
def wr(p, s): open(os.path.join(K, p), "w", encoding="utf-8").write(s)

def patch(path, marker, anchor, insert, tag, after=False):
    s = rd(path)
    if insert.strip() in s:
        print("  [skip] %-28s %s (already applied)" % (path, tag)); return
    i = s.find(marker)
    if i < 0:
        print("  [FAIL] %-28s %s: function marker not found" % (path, tag)); sys.exit(1)
    j = s.find(anchor, i)
    if j < 0:
        print("  [FAIL] %-28s %s: inner anchor not found" % (path, tag)); sys.exit(1)
    k = j + (len(anchor) if after else 0)
    wr(path, s[:k] + insert + s[k:])
    print("  [ok]   %-28s %s" % (path, tag))

# ---------------- 1. drivers/input/input.c (ksu_input_hook / safe mode) -------
patch("drivers/input/input.c",
      "void input_event(struct input_dev *dev,",
      "void input_event(struct input_dev *dev,",
      "#ifdef CONFIG_KSU\n"
      "extern bool ksu_input_hook __read_mostly;\n"
      "extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\n"
      "#endif\n\n",
      "extern", after=False)
patch("drivers/input/input.c",
      "void input_event(struct input_dev *dev,",
      "\tunsigned long flags;\n",
      "\n#ifdef CONFIG_KSU\n"
      "\tif (unlikely(ksu_input_hook))\n"
      "\t\tksu_handle_input_handle_event(&type, &code, &value);\n"
      "#endif\n",
      "call", after=True)

# ---------------- 2. fs/exec.c ----------------
patch("fs/exec.c",
      "int do_execve(struct filename *filename,",
      "int do_execve(struct filename *filename,",
      "#ifdef CONFIG_KSU\n"
      "extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n"
      "\t\t\t\tvoid *argv, void *envp, int *flags);\n"
      "#endif\n\n",
      "extern", after=False)
patch("fs/exec.c",
      "int do_execve(struct filename *filename,",
      "\treturn do_execveat_common(AT_FDCWD, filename, argv, envp, 0);\n",
      "#ifdef CONFIG_KSU\n"
      "\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n"
      "#endif\n",
      "do_execve call", after=False)
patch("fs/exec.c",
      "static int compat_do_execve(struct filename *filename,",
      "\treturn do_execveat_common(AT_FDCWD, filename, argv, envp, 0);\n",
      "#ifdef CONFIG_KSU /* 32-bit su and 32-on-64 */\n"
      "\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n"
      "#endif\n",
      "compat_do_execve call", after=False)

# ---------------- 3. fs/open.c ----------------
patch("fs/open.c",
      "SYSCALL_DEFINE3(faccessat, int, dfd,",
      "SYSCALL_DEFINE3(faccessat, int, dfd,",
      "#ifdef CONFIG_KSU\n"
      "extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n"
      "\t\t\t\tint *mode, int *flags);\n"
      "#endif\n\n",
      "extern", after=False)
patch("fs/open.c",
      "SYSCALL_DEFINE3(faccessat, int, dfd,",
      "\treturn do_faccessat(dfd, filename, mode);\n",
      "#ifdef CONFIG_KSU\n"
      "\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n"
      "#endif\n",
      "faccessat call", after=False)

# ---------------- 4. fs/read_write.c ----------------
patch("fs/read_write.c",
      "SYSCALL_DEFINE3(read, unsigned int, fd,",
      "SYSCALL_DEFINE3(read, unsigned int, fd,",
      "#ifdef CONFIG_KSU\n"
      "extern bool ksu_vfs_read_hook __read_mostly;\n"
      "extern void ksu_handle_sys_read(unsigned int fd);\n"
      "#endif\n\n",
      "extern", after=False)
patch("fs/read_write.c",
      "SYSCALL_DEFINE3(read, unsigned int, fd,",
      "\treturn ksys_read(fd, buf, count);\n",
      "#ifdef CONFIG_KSU\n"
      "\tif (unlikely(ksu_vfs_read_hook))\n"
      "\t\tksu_handle_sys_read(fd);\n"
      "#endif\n",
      "read call", after=False)

# ---------------- 5. fs/stat.c ----------------
patch("fs/stat.c",
      "SYSCALL_DEFINE4(newfstatat, int, dfd,",
      "SYSCALL_DEFINE4(newfstatat, int, dfd,",
      "#ifdef CONFIG_KSU\n"
      "extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n"
      "#endif\n\n",
      "extern", after=False)
patch("fs/stat.c",
      "SYSCALL_DEFINE4(newfstatat, int, dfd,",
      "\tint error;\n",
      "\n#ifdef CONFIG_KSU\n"
      "\tksu_handle_stat(&dfd, &filename, &flag);\n"
      "#endif\n",
      "newfstatat call", after=True)

# ---------------- 6. kernel/reboot.c ----------------
patch("kernel/reboot.c",
      "SYSCALL_DEFINE4(reboot, int, magic1,",
      "SYSCALL_DEFINE4(reboot, int, magic1,",
      "#ifdef CONFIG_KSU\n"
      "extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd,\n"
      "\t\t\t\t void __user **arg);\n"
      "#endif\n\n",
      "extern", after=False)
patch("kernel/reboot.c",
      "SYSCALL_DEFINE4(reboot, int, magic1,",
      "\tint ret = 0;\n",
      "\n#ifdef CONFIG_KSU\n"
      "\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n"
      "#endif\n",
      "reboot call", after=True)

print("  -> all KernelSU manual hooks installed")
