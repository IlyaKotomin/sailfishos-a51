#!/usr/bin/env python3
"""repo sync with a userspace bandwidth cap (no root needed).

Watches the NIC's rx_bytes counter and SIGSTOPs/SIGCONTs the sync process group
via a token bucket, so the long-run average download rate stays under CAP_MBIT.
Gaming keeps the rest of the line.
"""
import os, signal, subprocess, sys, time, pathlib

CAP_MBIT = float(os.environ.get("CAP_MBIT", "100"))   # megabits/sec
IFACE    = os.environ.get("IFACE", "enp3s0")
TICK     = 0.25                                        # seconds
CAP_BPS  = CAP_MBIT * 1_000_000 / 8                    # bytes/sec
ANDROID_ROOT = str(pathlib.Path.home() / "hadk")
LOGDIR   = pathlib.Path.home() / "a51-sfos-port/logs"
RXFILE   = f"/sys/class/net/{IFACE}/statistics/rx_bytes"

def rx():
    with open(RXFILE) as f: return int(f.read())

log    = open(LOGDIR / "repo-sync.log", "ab", buffering=0)
status = LOGDIR / "sync-status.txt"

env = dict(os.environ, PATH=f"{pathlib.Path.home()}/bin:" + os.environ["PATH"])
cmd = ["nice", "-n", "19", "ionice", "-c3",
       "repo", "sync", "-c", "-j3", "--no-tags"]
log.write(f"\n=== throttled sync start {time.strftime('%F %T')} cap={CAP_MBIT}Mbit ===\n".encode())
proc = subprocess.Popen(cmd, cwd=ANDROID_ROOT, env=env,
                        stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
pgid = os.getpgid(proc.pid)

allowance = CAP_BPS * TICK
paused = False
last = rx()
t0 = time.time()
samples = []
try:
    while proc.poll() is None:
        time.sleep(TICK)
        cur = rx(); used = cur - last; last = cur
        samples.append(used)
        if len(samples) > 40: samples.pop(0)
        allowance += CAP_BPS * TICK - used
        allowance = max(min(allowance, CAP_BPS), -CAP_BPS * 4)
        if allowance < 0 and not paused:
            os.killpg(pgid, signal.SIGSTOP); paused = True
        elif allowance >= 0 and paused:
            os.killpg(pgid, signal.SIGCONT); paused = False
        if int(time.time() - t0) % 10 == 0:
            avg = sum(samples) / (len(samples) * TICK) if samples else 0
            status.write_text(
                f"updated  {time.strftime('%F %T')}\n"
                f"cap      {CAP_MBIT:.0f} Mbit/s ({CAP_BPS/1e6:.1f} MB/s)\n"
                f"avg 10s  {avg*8/1e6:.1f} Mbit/s ({avg/1e6:.1f} MB/s)\n"
                f"state    {'PAUSED' if paused else 'running'}\n"
                f"elapsed  {int(time.time()-t0)//60} min\n")
finally:
    if paused:
        try: os.killpg(pgid, signal.SIGCONT)
        except ProcessLookupError: pass
rc = proc.wait()
log.write(f"=== sync exited rc={rc} at {time.strftime('%F %T')} ===\n".encode())
status.write_text(f"finished {time.strftime('%F %T')} rc={rc}\n")
sys.exit(rc)
