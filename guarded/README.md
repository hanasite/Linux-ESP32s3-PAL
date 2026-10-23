# PAL S3 Guarded MVP

Status: runtime-staged and boot-verified on 2026-10-23.

This directory is the runtime-staged Guarded MVP for the ESP32-S3 N16R8
Linux board. It does not require an image rebuild.

- `agent` is a non-root user in group `pal`; it cannot open `/dev/gpiochip0`
  or `/dev/i2c-0`.
- `palio` is a root `socat` listener on `/run/palio.sock`; each request runs
  `/etc/pal/broker.sh`, which validates `board.conf`, performs the I/O, and
  appends to `/etc/pal/audit.log`.
- `pal` is the agent CLI: `/etc/pal/pal gpio set LED_STATUS 1`,
  `/etc/pal/pal i2c read 0 0x48 0x00 1`, `/etc/pal/pal info`. A non-login
  SSH session may not have `/etc/pal` in PATH; export it or use the full path.
  Each command takes about one second: the client holds the socket open for
  1 s while the broker writes the audit record to jffs2.
- `pal-exec` runs MicroPython as `agent` with a heap cap and a watchdog kill.

Install as root on the board:

    tar -C guarded -cf - . | ssh root@192.168.101.30 \
      'rm -rf /tmp/guarded && mkdir -p /tmp/guarded && tar -C /tmp/guarded -xf -'
    ssh root@192.168.101.30 'sh /tmp/guarded/install.sh'

Run the compliance suite as root:

    ssh root@192.168.101.30 '/etc/pal/tests/compliance.sh'

Expected: every line `PASS`, ending with `ALL PASS`.

MVP limits: the manifest is `board.conf` (not `board.json`); I2C reads are
one byte; the audit record does not carry the peer UID; the agent can run
MicroPython directly and bypass the executor limits. The broker and the
root-only devices remain the hardware boundary.

Enforced now: pin names/owners, GPIO direction, `max_pulse_ms`, the I2C
address allow-list, and the audit log. Not yet enforced: `max_rate_hz`,
`max_duration_s`, and `max_heap_kb` (the agent can pass a larger `pal-exec`
timeout or heap); those move to Phase B.
