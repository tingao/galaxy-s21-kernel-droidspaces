# Firmware files removed from this repository

The rest of this tree is GPLv2 source. These eight files are binary firmware
blobs, which the GPL does not cover, so they are not redistributed here. They
are small and easy to restore from Samsung's official release.

## What is missing

| file | size | hardware |
|---|---|---|
| `range_sensor/p3_00_generic_xtalk_shape.bin` | 320 B | VL53L5CX range sensor crosstalk shape |
| `range_sensor/p3_vl53l5.bin` | 111072 B | VL53L5CX range sensor |
| `tsp_sec/y792_m1.bin` | 210152 B | Samsung touchscreen controller |
| `tsp_sec/y792_n2.bin` | 210176 B | Samsung touchscreen controller |
| `tsp_sec/y792_o3.bin` | 210200 B | Samsung touchscreen controller |
| `tsp_stm/fts9cu80f_q2.bin` | 120916 B | STMicro touchscreen controller |
| `tsp_zinitix/ztw522_b1.bin` | 45056 B | Zinitix touchscreen controller |
| `tsp_zinitix/ztw522_b2.bin` | 45056 B | Zinitix touchscreen controller |

## How to get them

1. Open https://opensource.samsung.com/uploadSearch?searchValue=SM-G9910
2. Find the row for build `G9910ZHSFHYL1` and download both archives:
   * `SM-G9910_HKTW_15_Opensource.zip` (base, version `G9910ZHUBHYD9`)
   * `SM-G9910_HKTW_15_Opensource_G9910ZHSFHYL1.zip` (delta, applied on top)
   The download button is behind an hCaptcha, so it has to be done in a browser.
3. Extract the base, then the delta over it. The delta carries its files under a
   `Kernel/` prefix, so strip that component:

   ```sh
   unzip SM-G9910_HKTW_15_Opensource.zip
   unzip -o SM-G9910_HKTW_15_Opensource_G9910ZHSFHYL1.zip
   ```

4. Copy the `firmware` directory from the extracted tree to this directory.
5. Check the restored files against the sizes above.

These files were retrieved from Samsung Open Source Release Center on 2026-09-17.
