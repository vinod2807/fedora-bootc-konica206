# Crash / freeze fixes for the target PC

These settings come from
[vinod2807/linux-pc-crash-fixes](https://github.com/vinod2807/linux-pc-crash-fixes),
which documents the Intel Core i5 650 (Clarkdale/Nehalem) freezes on this
machine.

The image installs them in two places:

| File | Purpose |
|---|---|
| `/usr/lib/bootc/kargs.d/90-linux-pc-crash-fixes.toml` | bootc-managed kernel arguments, applied at install and to existing systems on upgrade |
| `/etc/modprobe.d/90-linux-pc-crash-fixes.conf` | module options for `snd_hda_intel` |

Kernel arguments:

```
intel_idle.max_cstate=1
snd_hda_intel.power_save=0
snd_hda_intel.power_save_controller=0
```

`intel_idle.max_cstate=1` limits the CPU to C1, avoiding the deep C-states
that freeze this machine. The two HDA options disable codec/controller
power-saving transitions that can hang or pop on idle audio.

## Verify after installation or upgrade

```bash
cat /proc/cmdline
grep -E 'intel_idle|snd_hda' /proc/cmdline

cat /sys/module/intel_idle/parameters/max_cstate            # expect 1
cat /sys/module/snd_hda_intel/parameters/power_save         # expect 0
cat /sys/module/snd_hda_intel/parameters/power_save_controller  # expect N
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name       # expect POLL + C1
```

If an existing installation does not show the arguments after `bootc upgrade`,
check that the running deployment is the new one (`bootc status`) and reboot.
The kargs diff is applied when the new deployment is staged/applied.

## Reverting

These are release-level settings. To test without them, create a local
deployment with different kernel arguments, or remove the files from a fork and
rebuild. Do not delete `/usr/lib/bootc/kargs.d/90-linux-pc-crash-fixes.toml`
on a running system: it is part of the immutable `/usr` deployment.
