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
