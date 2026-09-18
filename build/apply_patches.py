import sys, io

def edit(path, pairs):
    src = open(path, encoding="utf-8").read()
    for i, (old, new, label) in enumerate(pairs):
        n = src.count(old)
        if n != 1:
            print(f"FAIL {path} [{label}]: expected 1 occurrence, found {n}")
            sys.exit(1)
        src = src.replace(old, new)
        print(f"  ok  {path}: {label}")
    open(path, "w", encoding="utf-8").write(src)

sched = "include/linux/sched.h"
user  = "include/linux/sched/user.h"

# ---- 001 intent: move task_struct sysvsem/sysvshm into KABI reserve slots ----
old_sysvipc = """#ifdef CONFIG_SYSVIPC
\tstruct sysv_sem\t\t\tsysvsem;
\tstruct sysv_shm\t\t\tsysvshm;
#endif
"""
new_sysvipc = """#ifdef CONFIG_SYSVIPC
\t// struct sysv_sem\t\t\tsysvsem;
\t// struct sysv_shm\t\t\tsysvshm;
#endif
"""

old_res = "\n".join([f"\tANDROID_KABI_RESERVE({i});" for i in range(1, 9)]) + "\n"
new_res = """\tANDROID_KABI_RESERVE(1);
\tANDROID_KABI_RESERVE(2);
#ifdef CONFIG_SYSVIPC
\tANDROID_KABI_USE(3, struct sysv_sem sysvsem);
\t_ANDROID_KABI_REPLACE(ANDROID_KABI_RESERVE(4); ANDROID_KABI_RESERVE(5), struct sysv_shm sysvshm);
#else
\tANDROID_KABI_RESERVE(3);
\tANDROID_KABI_RESERVE(4);
\tANDROID_KABI_RESERVE(5);
#endif
\tANDROID_KABI_RESERVE(6);
\tANDROID_KABI_RESERVE(7);
\tANDROID_KABI_RESERVE(8);
"""

edit(sched, [(old_sysvipc, new_sysvipc, "task_struct sysvsem/sysvshm -> commented"),
             (old_res,     new_res,     "reserve 3/4/5 -> KABI_USE/REPLACE")])

# ---- 002 intent, adapted: this tree has no ANDROID_OEM_DATA_ARRAY ----
old_mq = """#ifdef CONFIG_POSIX_MQUEUE
\t/* protected by mq_lock\t*/
\tunsigned long mq_bytes;\t/* How many bytes can be allocated to mqueue? */
#endif
"""
new_mq = """#ifdef CONFIG_POSIX_MQUEUE
\t/* protected by mq_lock\t*/
\t//unsigned long mq_bytes;\t/* How many bytes can be allocated to mqueue? */
#endif
"""

old_ures = """\tANDROID_KABI_RESERVE(1);
\tANDROID_KABI_RESERVE(2);
};
"""
new_ures = """#if defined(CONFIG_POSIX_MQUEUE)
\tANDROID_KABI_USE(1, unsigned long mq_bytes);
\tANDROID_KABI_RESERVE(2);
#else
\tANDROID_KABI_RESERVE(1);
\tANDROID_KABI_RESERVE(2);
#endif
};
"""

edit(user, [(old_mq, new_mq, "user_struct mq_bytes -> commented"),
            (old_ures, new_ures, "reserve 1/2 -> KABI_USE(mq_bytes)")])

print("BOTH PATCH INTENTS APPLIED")