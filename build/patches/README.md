# patches

Two kinds of change live in this directory, and they are not the same thing.

## `02-cgroup-prefix.patch`, a real patch file

A plain `patch -p1` applicable diff. See the file itself; it fixes GKI cgroup file naming, which
cgroup v2 consumers depend on.

## The kABI patches, applied by `../apply_patches.py`

These are **not** stored as `.patch` files. They are expressed as string replacements in
`../apply_patches.py`, because each one has to land in exactly one place and the script *asserts* that
(exactly one occurrence, or it aborts). A silently-failing fuzz match is worse than a hard failure.

They exist because this kernel must keep loading **54 prebuilt stock vendor modules**, and any exported
symbol whose CRC moves makes them refuse to load. Two features these kernels need, `SYSVIPC` and
`POSIX_MQUEUE`, add fields to `struct task_struct` and `struct user_struct`, which are in the type graph
genksyms walks. Naively enabling them moves thousands of CRCs.

The fix is Android's own kABI technique: put the new fields **inside the reserved slots** that the GKI
kABI already carves out, and hide the change from genksyms.

### Patch 001: `task_struct` sysvsem / sysvshm to KABI reserves 3/4/5

`include/linux/sched.h`

```diff
 #ifdef CONFIG_SYSVIPC
-	struct sysv_sem			sysvsem;
-	struct sysv_shm			sysvshm;
+	// struct sysv_sem			sysvsem;
+	// struct sysv_shm			sysvshm;
 #endif

-	ANDROID_KABI_RESERVE(1);  ...  ANDROID_KABI_RESERVE(8);
+	ANDROID_KABI_RESERVE(1);
+	ANDROID_KABI_RESERVE(2);
+#ifdef CONFIG_SYSVIPC
+	ANDROID_KABI_USE(3, struct sysv_sem sysvsem);
+	_ANDROID_KABI_REPLACE(ANDROID_KABI_RESERVE(4); ANDROID_KABI_RESERVE(5), struct sysv_shm sysvshm);
+#else
+	ANDROID_KABI_RESERVE(3);
+	ANDROID_KABI_RESERVE(4);
+	ANDROID_KABI_RESERVE(5);
+#endif
+	ANDROID_KABI_RESERVE(6);
+	ANDROID_KABI_RESERVE(7);
+	ANDROID_KABI_RESERVE(8);
```

### Patch 002: `user_struct.mq_bytes` to KABI reserve 1

`include/linux/sched/user.h`. Same technique; this tree has no `ANDROID_OEM_DATA_ARRAY`, so the
original upstream intent was adapted to the reserved slots.

```diff
 #ifdef CONFIG_POSIX_MQUEUE
 	/* protected by mq_lock	*/
-	unsigned long mq_bytes;
+	//unsigned long mq_bytes;
 #endif

-	ANDROID_KABI_RESERVE(1);
-	ANDROID_KABI_RESERVE(2);
+#if defined(CONFIG_POSIX_MQUEUE)
+	ANDROID_KABI_USE(1, unsigned long mq_bytes);
+	ANDROID_KABI_RESERVE(2);
+#else
+	ANDROID_KABI_RESERVE(1);
+	ANDROID_KABI_RESERVE(2);
+#endif
```

### Why `_ANDROID_KABI_REPLACE` makes this work

Under `#ifdef __GENKSYMS__` these macros collapse to their **original** forms. genksyms, the tool that
computes the CRCs, therefore walks exactly the type graph the stock kernel had, and emits the same
CRCs. The compiled kernel, built without `__GENKSYMS__`, gets the real fields in the reserved space.
The layout is genuinely unchanged; it is not merely hidden from a check.

There is a second instance of the same idea in `../fix_seccomp_kabi.py`, which handles KernelSU-Next's
injected `atomic_t filter_count` in `struct seccomp` the same way. On arm64 that field lands in existing
tail padding, so `sizeof(struct seccomp)` stays 16 and `offsetof(filter)` stays 8, verified with pahole
rather than assumed.

## Verifying that it actually worked

Never trust that the patches "look right". Check the CRCs:

```sh
python3 ../crcgate.py <stock>.symvers out/Module.symvers
```

Expected:

```
CRC CHANGES ON PRE-EXISTING SYMBOLS: 0
SYMBOLS LOST FROM MODIFIED BUILD:    0
NEW EXPORTED SYMBOLS:                0
VERDICT: kABI PRESERVED
```

All three published variants pass this gate. **If a build reports any change, do not flash it**, because
the vendor modules will fail to load and you lose Wi-Fi, audio and camera.
