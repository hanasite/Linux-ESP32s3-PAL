# PAL S3 Guarded MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working Guarded-mode MVP on the ESP32-S3 NOMMU Linux board: a non-root `agent` user, a root `palio` broker over a Unix socket, a name-based manifest, an audit log, a `pal-exec` MicroPython supervisor, and a compliance test suite — without rebuilding the image.

**Architecture:** A root-run `socat` listener creates `/run/palio.sock` and executes `/etc/pal/broker.sh` per connection. The broker validates a line protocol against `/etc/pal/board.conf`, calls `espctl` for GPIO and `i2cget/i2cset` for I2C, appends to `/etc/pal/audit.log`, and returns JSON. The `agent` user connects with the `pal` CLI; `pal-exec` runs MicroPython as `agent` in a new session with a watchdog kill and heap cap. The agent cannot open `/dev/gpiochip0` or `/dev/i2c-0` because they are root-only.

**Tech Stack:** BusyBox 1.36.1 ash, socat 1.8.1.3, awk, `espctl`, `i2cget/i2cset`, MicroPython (`-X heapsize`), `setsid`, `adduser/addgroup`, SSH/dropbear.

## Global Constraints

- Board: ESP32-S3 N16R8, Linux 7.2.4-forkbank (NOMMU), at `192.168.101.30`.
- `/dev/gpiochip0` and `/dev/i2c-0` are root-only; `/dev/mem` does not exist.
- `/` is read-only cramfs; `/etc` and `/home` are writable and persist across reboots.
- No image rebuild in this plan; changes live in `/etc` and `/home`. A rootfs overlay copy is included for later image builds.
- No `timeout`, no CPython, no compiler. Use `setsid` plus a shell watchdog.
- MicroPython supports `-X heapsize=<n>K`; default 131072.
- The broker runs as root via socat; the agent is non-root and in group `pal`.
- The MVP manifest is `board.conf` (line format), not `board.json`. Phase B migrates to JSON and a C broker.
- The audit log is `/etc/pal/audit.log`, `root:pal 0640`. Phase A logs actions but not the peer UID; Phase B adds `SO_PEERCRED`.
- The agent can bypass `pal-exec` limits by running MicroPython directly; the hardware boundary (broker plus root-only devices) still holds. Phase B enforces the executor.
- ASCII source files; BusyBox ash; no bashisms.
- Root SSH key access works. The agent public key is:
  `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN5X4VupfGYKwrJFGampkLW9IL1GcgWwouPIKpZGK+Vg claude-code@pal`
- Board SSH commands in this plan use the host alias `BOARD=192.168.101.30`.

## File Structure

```
guarded/
  install.sh              # run as root on the board; creates agent, modes, audit, starts broker
  board.conf              # line manifest: pins, I2C addresses, limits
  agent.pub               # authorized key for the agent user
  S38pal                  # init script; starts/stops the socat broker
  broker.sh               # root broker; one request per connection
  pal                     # agent-facing CLI; talks to /run/palio.sock
  pal-exec                # agent-facing MicroPython supervisor
  tests/compliance.sh     # root-run PASS/FAIL suite
  README.md               # install, commands, guarantees, limitations
```

Installed layout:

```
/etc/pal/board.conf       root:root 0644
/etc/pal/broker.sh        root:root 0700
/etc/pal/pal              root:root 0755
/etc/pal/pal-exec         root:root 0755
/etc/pal/audit.log        root:pal  0640
/etc/pal/tests/compliance.sh root:root 0700
/etc/init.d/S38pal        root:root 0755
/home/agent/              agent:pal
/home/agent/board/board.conf agent:pal 0644
/home/agent/.ssh/authorized_keys agent:pal 0600
```

---

### Task 1: Workspace, manifest, and agent key

**Files:**
- Create: `guarded/board.conf`
- Create: `guarded/agent.pub`
- Create: `guarded/README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `board.conf` line format consumed by `broker.sh` and `pal`; `agent.pub` consumed by `install.sh`.

- [ ] **Step 1: Create the work branch**

Run in `H:\ESP32idf\Linux-on-esp32-S3`:

```bash
git remote add fork https://v4.gh-proxy.org/https://github.com/hanasite/Linux-ESP32s3-PAL.git 2>/dev/null || true
git fetch fork
git checkout -b guarded-mvp fork/main
```

Expected: `Switched to a new branch 'guarded-mvp'`.

- [ ] **Step 2: Write `guarded/board.conf`**

```text
# PAL guarded manifest (MVP, line format).
# pin <name> <gpio> <dir> <owner>
pin LED_STATUS 21 out agent
pin TEMP_ALERT 4 in agent
pin RELAY_POWER 12 out system
# i2c <bus> <7-bit address>
i2c 0 0x48
i2c 0 0x76
# limit <name> <value>
limit max_pulse_ms 500
limit max_rate_hz 10
limit max_duration_s 30
limit max_heap_kb 256
```

- [ ] **Step 3: Write `guarded/agent.pub`**

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN5X4VupfGYKwrJFGampkLW9IL1GcgWwouPIKpZGK+Vg claude-code@pal
```

- [ ] **Step 4: Write `guarded/README.md`**

```markdown
# PAL S3 Guarded MVP

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
- `pal-exec` runs MicroPython as `agent` with a heap cap and a watchdog kill.

Install as root on the board:

    tar -C guarded -cf - . | ssh root@192.168.101.30 \
      'rm -rf /tmp/guarded && mkdir -p /tmp/guarded && tar -C /tmp/guarded -xf -'
    ssh root@192.168.101.30 'sh /tmp/guarded/install.sh'

Run the compliance suite as root:

    ssh root@192.168.101.30 '/etc/pal/tests/compliance.sh'

MVP limits: the manifest is `board.conf` (not `board.json`); I2C reads are
one byte; the audit record does not carry the peer UID; the agent can run
MicroPython directly and bypass the executor limits. The broker and the
root-only devices remain the hardware boundary.

Enforced now: pin names/owners, GPIO direction, `max_pulse_ms`, the I2C
address allow-list, and the audit log. Not yet enforced: `max_rate_hz`,
`max_duration_s`, and `max_heap_kb` (the agent can pass a larger `pal-exec`
timeout or heap); those move to Phase B.
```

- [ ] **Step 5: Verify the manifest parses**

Run locally:

```bash
awk '$1 == "pin" { print $2, $3, $4, $5 }' guarded/board.conf
```

Expected:

```text
LED_STATUS 21 out agent
TEMP_ALERT 4 in agent
RELAY_POWER 12 out system
```

- [ ] **Step 6: Commit**

```bash
git add guarded/board.conf guarded/agent.pub guarded/README.md
git commit -m "guarded: add manifest, agent key, and README"
```

---

### Task 2: Agent user, permissions, and init script

**Files:**
- Create: `guarded/install.sh`
- Create: `guarded/S38pal`

**Interfaces:**
- Consumes: `board.conf`, `agent.pub` from Task 1.
- Produces: `agent` user in group `pal`; `/etc/pal` and `/home/agent`; `/etc/init.d/S38pal`; the `pal` group; the audit log.

- [ ] **Step 1: Write the failing test**

On the board, before installing:

```bash
ssh -o BatchMode=yes agent@192.168.101.30 'id'
```

Expected: `Permission denied` or `user agent does not exist`.

- [ ] **Step 2: Write `guarded/install.sh`**

```sh
#!/bin/sh
set -eu
SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST=/etc/pal

[ "$(id -u)" = 0 ] || { echo "install.sh: must be root" >&2; exit 1; }

# group and user
grep -q '^pal:' /etc/group || addgroup -S pal
if ! id agent >/dev/null 2>&1; then
    adduser -D -h /home/agent -s /bin/sh -G pal agent
fi
addgroup agent pal 2>/dev/null || true

# directories
mkdir -p "$DEST" "$DEST/tests" /home/agent/work /home/agent/board /home/agent/.ssh

# files
for f in board.conf broker.sh pal pal-exec; do
    if [ -f "$SRC/$f" ]; then
        cp "$SRC/$f" "$DEST/$f"
    fi
done
if [ -f "$SRC/tests/compliance.sh" ]; then
    cp "$SRC/tests/compliance.sh" "$DEST/tests/compliance.sh"
fi

# modes
chown -R root:root "$DEST"
chmod 755 "$DEST" "$DEST/tests"
chmod 644 "$DEST/board.conf"
if [ -f "$DEST/broker.sh" ]; then chmod 700 "$DEST/broker.sh"; fi
if [ -f "$DEST/pal" ]; then chmod 755 "$DEST/pal"; fi
if [ -f "$DEST/pal-exec" ]; then chmod 755 "$DEST/pal-exec"; fi
if [ -f "$DEST/tests/compliance.sh" ]; then chmod 700 "$DEST/tests/compliance.sh"; fi

# agent-visible manifest copy
cp "$DEST/board.conf" /home/agent/board/board.conf
chown agent:agent /home/agent/board/board.conf
chmod 644 /home/agent/board/board.conf

# audit log (persistent, root:pal 0640)
touch "$DEST/audit.log"
chown root:pal "$DEST/audit.log"
chmod 640 "$DEST/audit.log"

# agent SSH key
if [ -f "$SRC/agent.pub" ]; then
    touch /home/agent/.ssh/authorized_keys
    cat "$SRC/agent.pub" >> /home/agent/.ssh/authorized_keys
    sort -u /home/agent/.ssh/authorized_keys > /home/agent/.ssh/authorized_keys.tmp
    mv /home/agent/.ssh/authorized_keys.tmp /home/agent/.ssh/authorized_keys
    chown -R agent:pal /home/agent/.ssh
    chmod 700 /home/agent/.ssh
    chmod 600 /home/agent/.ssh/authorized_keys
fi

# agent PATH
if [ -f /home/agent/.profile ]; then
    grep -q '/etc/pal' /home/agent/.profile || echo 'export PATH=/etc/pal:$PATH' >> /home/agent/.profile
    chown agent:agent /home/agent/.profile
fi

# init script
cp "$SRC/S38pal" /etc/init.d/S38pal
chown root:root /etc/init.d/S38pal
chmod 755 /etc/init.d/S38pal

/etc/init.d/S38pal restart || true
echo "pal guarded MVP installed"
```

- [ ] **Step 3: Write `guarded/S38pal`**

```sh
#!/bin/sh
PAL=/etc/pal
SOCK=/run/palio.sock
PID=/run/palio.pid

start() {
    [ -x "$PAL/broker.sh" ] || exit 0
    [ -f "$PAL/board.conf" ] || exit 0
    mkdir -p /run
    if [ -f "$PID" ]; then
        kill "$(cat "$PID")" 2>/dev/null || true
    fi
    rm -f "$PID" "$SOCK"
    setsid socat UNIX-LISTEN:"$SOCK",fork,max-children=4,unlink-early,mode=0660,group=pal EXEC:"$PAL/broker.sh" >/dev/null 2>&1 &
    echo $! > "$PID"
    n=0
    while [ ! -S "$SOCK" ] && [ "$n" -lt 5 ]; do
        sleep 1
        n=$((n + 1))
    done
    if [ ! -S "$SOCK" ]; then
        echo "S38pal: broker socket not created" >&2
        return 1
    fi
}

stop() {
    if [ -f "$PID" ]; then
        kill "$(cat "$PID")" 2>/dev/null || true
    fi
    rm -f "$PID" "$SOCK"
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart|reload) stop; start ;;
    *) echo "usage: $0 {start|stop|restart}" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Deploy and install**

From the repo root:

```bash
tar -C guarded -cf - . | ssh root@192.168.101.30 \
  'rm -rf /tmp/guarded && mkdir -p /tmp/guarded && tar -C /tmp/guarded -xf -'
ssh root@192.168.101.30 'sh /tmp/guarded/install.sh'
```

Expected: `pal guarded MVP installed`.

- [ ] **Step 5: Verify the agent and the device boundary**

```bash
ssh -o BatchMode=yes agent@192.168.101.30 'id'
ssh -o BatchMode=yes agent@192.168.101.30 'cat /dev/gpiochip0'
ssh -o BatchMode=yes agent@192.168.101.30 'cat /dev/i2c-0'
```

Expected:

```text
uid=1000(agent) gid=1000(pal) groups=1000(pal)
cat: /dev/gpiochip0: Permission denied
cat: /dev/i2c-0: Permission denied
```

UID/GID numbers may differ; the output must contain `agent`, `pal` in the group list, and two `Permission denied` lines.

- [ ] **Step 6: Commit**

```bash
git add guarded/install.sh guarded/S38pal
git commit -m "guarded: add agent user, permissions, and init script"
```

---

### Task 3: `palio` broker and `pal` CLI

**Files:**
- Create: `guarded/broker.sh`
- Create: `guarded/pal`

**Interfaces:**
- Consumes: `board.conf`, `agent` user, `/run/palio.sock` from Task 2.
- Produces: `/etc/pal/broker.sh`, `/etc/pal/pal`; the line protocol:
  `gpio set|get|pulse <name> [value|ms]`, `i2c read|write <bus> <addr> <reg> [value]`, `info`.

- [ ] **Step 1: Write the failing test**

Before installing the broker:

```bash
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal info'
```

Expected: `No such file or directory` or `broker not running`.

- [ ] **Step 2: Write `guarded/broker.sh`**

```sh
#!/bin/sh
# palio broker: one request per connection. Started as root by socat.
MANIFEST=/etc/pal/board.conf
AUDIT=/etc/pal/audit.log

log() {
    printf '%s peer=pal action=%s target=%s value=%s result=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)" \
        "$1" "$2" "$3" "$4" >> "$AUDIT"
}

reply() { printf '%s\n' "$1"; }
deny() { log "$1" "$2" "$3" "denied:$4"; reply "{\"ok\":false,\"error\":\"$4\"}"; exit 0; }

pin_field() {
    awk -v n="$1" -v f="$2" '$1=="pin" && $2==n {print $f; exit}' "$MANIFEST"
}

i2c_allowed() {
    awk -v b="$1" -v a="$2" '$1=="i2c" && $2==b && $3==a {found=1} END{exit !found}' "$MANIFEST"
}

limit_value() {
    awk -v k="$1" '$1=="limit" && $2==k {print $3; exit}' "$MANIFEST"
}

read -r line || exit 1
line=$(printf '%s' "$line" | tr -d '\r')
set -- $line
cmd=${1:-}

case "$cmd" in
    gpio)
        op=${2:-}
        name=${3:-}
        case "$name" in ''|*[!A-Za-z0-9_]*) deny "gpio.$op" "$name" "" "bad name" ;; esac
        pin=$(pin_field "$name" 3)
        dir=$(pin_field "$name" 4)
        owner=$(pin_field "$name" 5)
        [ -n "$pin" ] || deny "gpio.$op" "$name" "" "not in manifest"
        [ "$owner" = agent ] || deny "gpio.$op" "$name" "" "owner is system"
        case "$op" in
            set)
                [ "$dir" = out ] || deny gpio.set "$name" "" "not an output"
                val=${4:-}
                case "$val" in 0|1) ;; *) deny gpio.set "$name" "$val" "bad value" ;; esac
                if espctl gpio set "$pin" "$val" >/dev/null 2>&1; then
                    log gpio.set "$name" "$val" ok
                    reply "{\"ok\":true,\"cmd\":\"gpio.set\",\"name\":\"$name\",\"value\":$val}"
                else
                    deny gpio.set "$name" "$val" "io error"
                fi
                ;;
            get)
                out=$(espctl gpio get "$pin" 2>&1)
                if [ $? -ne 0 ]; then deny gpio.get "$name" "" "io error"; fi
                val=$(printf '%s\n' "$out" | awk '{print $NF}')
                log gpio.get "$name" "$val" ok
                reply "{\"ok\":true,\"cmd\":\"gpio.get\",\"name\":\"$name\",\"value\":$val}"
                ;;
            pulse)
                [ "$dir" = out ] || deny gpio.pulse "$name" "" "not an output"
                ms=${4:-}
                case "$ms" in ''|*[!0-9]*) deny gpio.pulse "$name" "$ms" "bad ms" ;; esac
                max=$(limit_value max_pulse_ms)
                if [ -n "$max" ] && [ "$ms" -gt "$max" ]; then
                    deny gpio.pulse "$name" "$ms" "above max_pulse_ms"
                fi
                espctl gpio set "$pin" 1 >/dev/null 2>&1 || deny gpio.pulse "$name" "$ms" "io error"
                usleep $((ms * 1000))
                espctl gpio set "$pin" 0 >/dev/null 2>&1
                log gpio.pulse "$name" "$ms" ok
                reply "{\"ok\":true,\"cmd\":\"gpio.pulse\",\"name\":\"$name\",\"ms\":$ms}"
                ;;
            *)
                deny "gpio.$op" "$name" "" "unknown op"
                ;;
        esac
        ;;
    i2c)
        op=${2:-}
        bus=${3:-}
        addr=${4:-}
        case "$bus" in ''|*[!0-9]*) deny "i2c.$op" "$bus/$addr" "" "bad bus" ;; esac
        case "$addr" in 0x[0-9A-Fa-f][0-9A-Fa-f]) ;; *) deny "i2c.$op" "$bus/$addr" "" "bad address" ;; esac
        i2c_allowed "$bus" "$addr" || deny "i2c.$op" "$bus/$addr" "" "address not in manifest"
        case "$op" in
            read)
                reg=${5:-}
                len=${6:-}
                case "$reg" in 0x[0-9A-Fa-f][0-9A-Fa-f]) ;; *) deny i2c.read "$bus/$addr/$reg" "$len" "bad register" ;; esac
                [ "$len" = 1 ] || deny i2c.read "$bus/$addr/$reg" "$len" "only length 1 in MVP"
                val=$(i2cget -y "$bus" "$addr" "$reg" 2>/dev/null)
                if [ $? -ne 0 ] || [ -z "$val" ]; then deny i2c.read "$bus/$addr/$reg" "$len" "io error"; fi
                log i2c.read "$bus/$addr/$reg" "$len" ok
                reply "{\"ok\":true,\"cmd\":\"i2c.read\",\"bus\":$bus,\"addr\":\"$addr\",\"reg\":\"$reg\",\"value\":\"$val\"}"
                ;;
            write)
                reg=${5:-}
                val=${6:-}
                case "$reg" in 0x[0-9A-Fa-f][0-9A-Fa-f]) ;; *) deny i2c.write "$bus/$addr/$reg" "$val" "bad register" ;; esac
                case "$val" in 0x[0-9A-Fa-f][0-9A-Fa-f]) ;; *) deny i2c.write "$bus/$addr/$reg" "$val" "bad value" ;; esac
                if i2cset -y "$bus" "$addr" "$reg" "$val" 2>/dev/null; then
                    log i2c.write "$bus/$addr/$reg" "$val" ok
                    reply "{\"ok\":true,\"cmd\":\"i2c.write\",\"bus\":$bus,\"addr\":\"$addr\",\"reg\":\"$reg\",\"value\":\"$val\"}"
                else
                    deny i2c.write "$bus/$addr/$reg" "$val" "io error"
                fi
                ;;
            *)
                deny "i2c.$op" "$bus/$addr" "" "unknown op"
                ;;
        esac
        ;;
    info)
        reply "{\"ok\":true,\"broker\":\"palio-mvp\",\"manifest\":\"board.conf\"}"
        ;;
    *)
        deny "${cmd:-none}" "" "" "unknown command"
        ;;
esac
```

- [ ] **Step 3: Write `guarded/pal`**

```sh
#!/bin/sh
SOCK=/run/palio.sock
if [ ! -S "$SOCK" ]; then
    echo '{"ok":false,"error":"broker not running"}'
    exit 1
fi
resp=$( { printf '%s\n' "$*"; usleep 1000000; } | socat - UNIX-CONNECT:"$SOCK" )
rc=$?
printf '%s\n' "$resp"
if [ "$rc" -ne 0 ]; then exit "$rc"; fi
case "$resp" in
    *'"ok":false'*) exit 1 ;;
esac
exit 0
```

The `usleep 1000000` keepalive is required: socat closes the socket when
stdin reaches EOF, and the broker writes the audit record to jffs2 before
replying. Without it the reply is lost. MicroPython's `AF_UNIX` connect
returns `EINVAL` on this port, so this stays a socat client. Each `pal`
command takes about one second.

- [ ] **Step 4: Deploy and restart**

```bash
tar -C guarded -cf - . | ssh root@192.168.101.30 \
  'rm -rf /tmp/guarded && mkdir -p /tmp/guarded && tar -C /tmp/guarded -xf -'
ssh root@192.168.101.30 'sh /tmp/guarded/install.sh'
```

Expected: `pal guarded MVP installed`.

- [ ] **Step 5: Test allowed and denied GPIO**

```bash
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal info'
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal gpio set LED_STATUS 1'
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal gpio get LED_STATUS'
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal gpio set RELAY_POWER 1'
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal gpio set NOPE 1'
```

Expected:

```text
{"ok":true,"broker":"palio-mvp","manifest":"board.conf"}
{"ok":true,"cmd":"gpio.set","name":"LED_STATUS","value":1}
{"ok":true,"cmd":"gpio.get","name":"LED_STATUS","value":1}
{"ok":false,"error":"owner is system"}
{"ok":false,"error":"not in manifest"}
```

The last two commands exit non-zero because `pal` maps `"ok":false` to exit 1.

- [ ] **Step 6: Test I2C allow-list and audit**

```bash
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal i2c read 0 0x50 0x00 1'
ssh -o BatchMode=yes agent@192.168.101.30 'tail -5 /etc/pal/audit.log'
ssh -o BatchMode=yes agent@192.168.101.30 'echo x >> /etc/pal/audit.log'
```

Expected:

```text
{"ok":false,"error":"address not in manifest"}
... recent audit lines ...
sh: can't create /etc/pal/audit.log: Permission denied
```

The positive I2C path (`0x48`) requires a device on bus 0; with no device it returns `{"ok":false,"error":"io error"}`, which still proves the allow-list passed. Do not treat the I/O error as a broker failure.

- [ ] **Step 7: Commit**

```bash
git add guarded/broker.sh guarded/pal
git commit -m "guarded: add socat broker and pal CLI"
```

---

### Task 4: `pal-exec` MicroPython supervisor

**Files:**
- Create: `guarded/pal-exec`

**Interfaces:**
- Consumes: `agent` user, `/home/agent/work`, `micropython`, `setsid`.
- Produces: `pal-exec run FILE [TIMEOUT_S] [HEAP_KB]`; prints up to 4096 bytes of output and a final `[pal-exec] exit=N ...` line.

- [ ] **Step 1: Write the failing test**

Before installing `pal-exec`:

```bash
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal-exec run /home/agent/work/ok.py'
```

Expected: `No such file or directory`.

- [ ] **Step 2: Write `guarded/pal-exec`**

```sh
#!/bin/sh
# usage: pal-exec run FILE [TIMEOUT_S] [HEAP_KB]
cmd=${1:-}
file=${2:-}
timeout=${3:-30}
heap=${4:-256}

if [ "$cmd" != run ] || [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "usage: pal-exec run FILE [TIMEOUT_S] [HEAP_KB]" >&2
    exit 2
fi
case "$timeout" in ''|*[!0-9]*) echo "pal-exec: bad timeout" >&2; exit 2 ;; esac
case "$heap" in ''|*[!0-9]*) echo "pal-exec: bad heap" >&2; exit 2 ;; esac

out=$(mktemp /tmp/pal-exec.XXXXXX) || exit 1
setsid micropython -X heapsize="${heap}K" "$file" >"$out" 2>&1 &
pid=$!
(
    sleep "$timeout"
    kill -TERM -"$pid" 2>/dev/null
    sleep 1
    kill -KILL -"$pid" 2>/dev/null
) &
wd=$!
wait "$pid"
rc=$?
kill "$wd" 2>/dev/null
head -c 4096 "$out"
rm -f "$out"
echo "[pal-exec] exit=$rc timeout=${timeout}s heap=${heap}K"
[ "$rc" -eq 0 ] || exit "$rc"
```

- [ ] **Step 3: Deploy**

```bash
tar -C guarded -cf - . | ssh root@192.168.101.30 \
  'rm -rf /tmp/guarded && mkdir -p /tmp/guarded && tar -C /tmp/guarded -xf -'
ssh root@192.168.101.30 'sh /tmp/guarded/install.sh'
```

- [ ] **Step 4: Test normal output and timeout**

Create the test scripts as the agent:

```bash
ssh -o BatchMode=yes agent@192.168.101.30 'cat > /home/agent/work/ok.py <<PY
print("hello from micropython")
PY'
ssh -o BatchMode=yes agent@192.168.101.30 'cat > /home/agent/work/spin.py <<PY
while True:
    pass
PY'
```

Run:

```bash
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal-exec run /home/agent/work/ok.py 5 64'
time ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal-exec run /home/agent/work/spin.py 2 64'
```

Expected for the first: `hello from micropython`, then `[pal-exec] exit=0 timeout=5s heap=64K`, exit 0.

Expected for the second: no output except `[pal-exec] exit=143 ...` (or `137`), exit non-zero, wall time about 2-3 seconds.

- [ ] **Step 5: Test the heap cap and output cap**

```bash
ssh -o BatchMode=yes agent@192.168.101.30 'cat > /home/agent/work/mem.py <<PY
a = []
while True:
    a.append("x" * 1024)
PY'
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal-exec run /home/agent/work/mem.py 5 32'
ssh -o BatchMode=yes agent@192.168.101.30 'cat > /home/agent/work/loud.py <<PY
for i in range(10000):
    print(i)
PY'
ssh -o BatchMode=yes agent@192.168.101.30 '/etc/pal/pal-exec run /home/agent/work/loud.py 10 128' | wc -c
```

Expected: the heap test ends with `MemoryError` and a non-zero exit; the output of the loud test is capped at 4096 bytes plus the final `[pal-exec]` line (well under 4200 bytes).

- [ ] **Step 6: Commit**

```bash
git add guarded/pal-exec
git commit -m "guarded: add MicroPython supervisor with timeout and heap cap"
```

---

### Task 5: Compliance suite, persistence, and docs

**Files:**
- Create: `guarded/tests/compliance.sh`
- Modify: `guarded/README.md` (add the compliance command)
- Copy: `guarded/S38pal` and `guarded/*.sh`/`pal*`/`board.conf` into the upstream rootfs overlay for later image builds.

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: a root-run PASS/FAIL suite; a rootfs overlay copy for a future Buildroot rebuild.

- [ ] **Step 1: Write `guarded/tests/compliance.sh`**

```sh
#!/bin/sh
# Run as root on the board: /etc/pal/tests/compliance.sh
fail=0
as_agent() { su agent -c "$1"; }
expect_ok() {
    name=$1; cmd=$2
    if as_agent "$cmd" >/dev/null 2>&1; then
        echo "PASS $name"
    else
        echo "FAIL $name"
        fail=1
    fi
}
expect_deny() {
    name=$1; cmd=$2
    if as_agent "$cmd" >/dev/null 2>&1; then
        echo "FAIL $name (allowed)"
        fail=1
    else
        echo "PASS $name"
    fi
}

expect_ok "agent can run id" 'id'
expect_deny "agent cannot read gpiochip" 'cat /dev/gpiochip0'
expect_deny "agent cannot read i2c" 'cat /dev/i2c-0'
expect_ok "pal info" '/etc/pal/pal info'
expect_ok "gpio set allowed pin" '/etc/pal/pal gpio set LED_STATUS 1'
expect_ok "gpio get allowed pin" '/etc/pal/pal gpio get LED_STATUS'
expect_ok "gpio clear allowed pin" '/etc/pal/pal gpio set LED_STATUS 0'
expect_deny "gpio system pin" '/etc/pal/pal gpio set RELAY_POWER 1'
expect_deny "gpio unknown name" '/etc/pal/pal gpio set NOPE 1'
expect_deny "i2c address not allowed" '/etc/pal/pal i2c read 0 0x50 0x00 1'
expect_ok "agent can read audit" 'cat /etc/pal/audit.log'
expect_deny "agent cannot write audit" 'echo x >> /etc/pal/audit.log'

cat > /home/agent/work/spin.py <<'PY'
while True:
    pass
PY
chown agent:pal /home/agent/work/spin.py
if as_agent '/etc/pal/pal-exec run /home/agent/work/spin.py 2 64' >/tmp/pal-exec-spin.log 2>&1; then
    echo "FAIL pal-exec timeout (returned 0)"
    fail=1
else
    echo "PASS pal-exec timeout"
fi
if grep -q 'exit=1[34][0-9]' /tmp/pal-exec-spin.log; then
    echo "PASS pal-exec killed"
else
    echo "FAIL pal-exec killed"
    fail=1
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
```

- [ ] **Step 2: Deploy and run the suite**

```bash
tar -C guarded -cf - . | ssh root@192.168.101.30 \
  'rm -rf /tmp/guarded && mkdir -p /tmp/guarded && tar -C /tmp/guarded -xf -'
ssh root@192.168.101.30 'sh /tmp/guarded/install.sh'
ssh root@192.168.101.30 '/etc/pal/tests/compliance.sh'
```

Expected: every line starts with `PASS`, ending with `ALL PASS`, exit 0.

- [ ] **Step 3: Copy the runtime files into the rootfs overlay**

This makes the same files part of a future image build. The running board already has them in `/etc` and `/home`; no rebuild is required for the MVP.

```bash
OVERLAY=H:/ESP32idf/Linux-on-esp32-S3/new-files/board/espressif/esp32s3/rootfs_overlay
mkdir -p "$OVERLAY/etc/pal/tests"
cp guarded/board.conf guarded/broker.sh guarded/pal guarded/pal-exec "$OVERLAY/etc/pal/"
cp guarded/tests/compliance.sh "$OVERLAY/etc/pal/tests/"
cp guarded/S38pal "$OVERLAY/etc/init.d/S38pal"
cp guarded/install.sh "$OVERLAY/etc/pal/install.sh"
chmod 700 "$OVERLAY/etc/pal/broker.sh" "$OVERLAY/etc/pal/install.sh"
chmod 755 "$OVERLAY/etc/pal/pal" "$OVERLAY/etc/pal/pal-exec" "$OVERLAY/etc/init.d/S38pal"
chmod 700 "$OVERLAY/etc/pal/tests/compliance.sh"
chmod 644 "$OVERLAY/etc/pal/board.conf"
```

The overlay still needs an image-build step to create the `agent` user, install the key, and start `S38pal`; the runtime `install.sh` is the reference for that boot logic. A clean image build is Phase B.

- [ ] **Step 4: Update `guarded/README.md` with the compliance command**

Append:

```markdown
## Compliance

Run as root on the board:

    /etc/pal/tests/compliance.sh

Expected: every line `PASS`, ending with `ALL PASS`.
```

- [ ] **Step 5: Commit**

```bash
git add guarded/tests/compliance.sh guarded/README.md
git commit -m "guarded: add compliance suite and image overlay notes"
```

- [x] **Step 6: Record the result**

```bash
ssh root@192.168.101.30 'uname -a; cat /proc/uptime; ls -l /etc/pal; tail -3 /etc/pal/audit.log'
```

Paste the output into the task log. The MVP is complete when the compliance suite prints `ALL PASS` and the agent cannot read the device nodes.

Recorded 2026-10-23: compliance `ALL PASS`; after reboot, uptime 61 s, `/etc/init.d/S38pal` started socat (PID 82), `/run/palio.sock` present, and `agent@192.168.101.30 /etc/pal/pal info` returned `{"ok":true,"broker":"palio-mvp","manifest":"board.conf"}`.

---

## Phase B (out of scope for this plan)

Phase B turns the runtime MVP into an image-level Guarded mode:

1. Replace the shell broker with a small C `palio` daemon using `SO_PEERCRED` for the authenticated peer UID, `board.json` (jsmn or a strict parser), rate limits, and the spec's JSON responses.
2. Build the daemon with the Xtensa toolchain in the upstream build container; install it in the rootfs overlay; rebuild and flash the image.
3. Force the agent through `pal-exec` (restricted SSH command or a restricted shell) so the heap/time limits cannot be bypassed.
4. Generate `board.json` from the line manifest and update `docs/s3-profile.md`/`docs/s3-compliance.md` to the implemented behavior.
5. Run the full compliance suite on a clean flash, not just a runtime-staged board.
