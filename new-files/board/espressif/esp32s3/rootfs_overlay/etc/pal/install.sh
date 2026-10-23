#!/bin/sh
set -e
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
chown agent:pal /home/agent/board/board.conf
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
    chown agent:pal /home/agent/.profile
fi

# init script
cp "$SRC/S38pal" /etc/init.d/S38pal
chown root:root /etc/init.d/S38pal
chmod 755 /etc/init.d/S38pal

/etc/init.d/S38pal restart || true
echo "pal guarded MVP installed"
