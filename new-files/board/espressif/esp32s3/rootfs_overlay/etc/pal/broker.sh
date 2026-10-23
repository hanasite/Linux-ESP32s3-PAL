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
