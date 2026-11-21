#!/system/bin/sh
MODDIR=${0%/*}
CONFIG="$MODDIR/config.conf"
GAMES_CONF="$MODDIR/games.conf"
SWITCH_CACHE="$MODDIR/active_switch.conf"

# Wait until Android boot completes
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Clear previous boot's NONE cache so a kernel update or fresh boot gets one clean probe
if [ -f "$SWITCH_CACHE" ] && [ "$(cat "$SWITCH_CACHE" 2>/dev/null)" = "NONE" ]; then
    rm -f "$SWITCH_CACHE"
fi

# Initialize default config if missing
if [ ! -f "$CONFIG" ]; then
    cat <<EOF > "$CONFIG"
SMART_ENABLE=1
MAX_LIMIT=80
RESUME_LIMIT=75
FORCE_BYPASS=0
NOTIF_ENABLE=1
CHARGE_SPEED=0
THERMAL_ENABLE=1
CHARGE_100_ONCE=0
GAME_BYPASS=0
EOF
fi

# Initialize default games list if missing
if [ ! -f "$GAMES_CONF" ]; then
    cat <<EOF > "$GAMES_CONF"
com.pubg.imobile
com.tencent.ig
com.dts.freefireth
com.dts.freefiremax
com.miHoYo.GenshinImpact
com.activision.callofduty.shooter
com.mobile.legends
com.garena.game.codm
com.HoYoverse.hkrpgoversea
com.kurogame.wutheringwaves.global
EOF
fi

# Dynamic max values for current and control limit nodes
DEF_CCC="12000000"
if [ -f "/sys/class/power_supply/battery/constant_charge_current_max" ]; then
    RAW_CCC=$(cat /sys/class/power_supply/battery/constant_charge_current_max 2>/dev/null | tr -d ' \n\r')
    if [ -n "$RAW_CCC" ] && [ "$RAW_CCC" -gt 500000 ] 2>/dev/null; then
        DEF_CCC="$RAW_CCC"
    fi
fi

CCL_MAX="1"
if [ -f "/sys/class/power_supply/battery/charge_control_limit_max" ]; then
    RAW_CCL=$(cat /sys/class/power_supply/battery/charge_control_limit_max 2>/dev/null | tr -d ' \n\r')
    if [ -n "$RAW_CCL" ] && [ "$RAW_CCL" -gt 0 ] 2>/dev/null; then
        CCL_MAX="$RAW_CCL"
    fi
fi

# Priority-ordered charging switch candidates: PATH|PAUSE_VAL|RESUME_VAL
# Excludes input_suspend nodes that cause battery discharge instead of true bypass/idle charging
SWITCH_LIST="
/sys/class/power_supply/battery/charging_enabled|0|1
/sys/class/power_supply/battery/battery_charging_enabled|0|1
/sys/class/power_supply/battery/charge_disable|1|0
/sys/class/power_supply/battery/constant_charge_current|0|$DEF_CCC
/sys/class/power_supply/battery/charge_control_limit|$CCL_MAX|0
/sys/class/qcom-battery/restrict_chg|1|0
/sys/class/hw_power/charger/charge_data/enable_charger|0|1
/sys/devices/platform/battery/Charging_Enable|0|1
/sys/devices/platform/mt-battery/disable_charger|1|0
/sys/devices/platform/soc/soc:google,charger/charge_disable|1|0
/sys/kernel/debug/google_charger/chg_suspend|1|0
/sys/class/power_supply/battery/store_mode|1|0
/sys/class/power_supply/battery/batt_slate_mode|1|0
/sys/class/power_supply/battery/bd_trickle_cnt|1|0
/sys/class/power_supply/battery/op_disable_charge|1|0
/sys/class/power_supply/battery/mmi_charging_enable|0|1
/proc/driver/charger_limit_enable|1|0
/sys/class/oplus_chg/battery/mmi_charging_enable|0|1
/sys/class/oplus_chg/battery/charging_enable|0|1
"

send_notif() {
    TITLE="$1"
    MSG="$2"
    if [ "$NOTIF_ENABLE" = "1" ]; then
        su -lp 2000 -c "cmd notification post -S bigtext -t '$TITLE' 'smart_bypass_charging' '$MSG'" >/dev/null 2>&1
    fi
}

write_lock() {
    if [ -f "$1" ]; then
        chmod 0644 "$1" 2>/dev/null
        echo "$2" > "$1" 2>/dev/null
        chmod 0444 "$1" 2>/dev/null
    fi
}

write_unlock() {
    if [ -f "$1" ]; then
        chmod 0644 "$1" 2>/dev/null
        echo "$2" > "$1" 2>/dev/null
    fi
}

# Verify if charging has actually stopped or entered idle/bypass state
is_charging_paused() {
    STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
    if [ "$STATUS" = "Not charging" ] || [ "$STATUS" = "Full" ]; then
        return 0
    fi
    # Do not count battery discharging (e.g., input_suspend) as valid bypass charging
    if [ "$STATUS" = "Discharging" ]; then
        return 1
    fi
    # If absolute battery current is less than 100mA (100000 uA), charging is effectively paused (idle/bypass)
    if [ -f "/sys/class/power_supply/battery/current_now" ]; then
        CURR=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null | tr -d ' \n\r')
        ABS_CURR=${CURR#-}
        if [ -n "$ABS_CURR" ] && [ "$ABS_CURR" -lt 100000 ] 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Auto-detect and cache the single working switch for this device
detect_working_switch() {
    if [ -f "$SWITCH_CACHE" ]; then
        CACHED=$(cat "$SWITCH_CACHE" 2>/dev/null)
        # Do not re-probe if failure was already cached
        if [ "$CACHED" = "NONE" ]; then
            return 1
        fi
        NODE=$(echo "$CACHED" | cut -d'|' -f1)
        if [ -n "$NODE" ] && [ -f "$NODE" ]; then
            return 0
        fi
    fi

    for entry in $SWITCH_LIST; do
        NODE=$(echo "$entry" | cut -d'|' -f1)
        OFF_VAL=$(echo "$entry" | cut -d'|' -f2)
        ON_VAL=$(echo "$entry" | cut -d'|' -f3)

        if [ -f "$NODE" ]; then
            # Poll up to 3 times (6s total) to allow fuel gauge current_now filter to settle
            for _try in 1 2 3; do
                write_lock "$NODE" "$OFF_VAL"
                sleep 2
                if is_charging_paused; then
                    echo "$entry" > "$SWITCH_CACHE"
                    return 0
                fi
            done
            write_unlock "$NODE" "$ON_VAL"
            sleep 1
        fi
    done

    # Cache failure so unsupported kernels are not re-probed every 2 seconds
    echo "NONE" > "$SWITCH_CACHE"
    return 1
}

apply_switch() {
    ACTION="$1"
    if [ "$ACTION" = "off" ]; then
        if ! detect_working_switch; then
            return 1
        fi
    else
        if [ ! -f "$SWITCH_CACHE" ]; then
            return 1
        fi
    fi

    CACHED=$(cat "$SWITCH_CACHE" 2>/dev/null)
    if [ -z "$CACHED" ] || [ "$CACHED" = "NONE" ]; then
        return 1
    fi

    NODE=$(echo "$CACHED" | cut -d'|' -f1)
    OFF_VAL=$(echo "$CACHED" | cut -d'|' -f2)
    ON_VAL=$(echo "$CACHED" | cut -d'|' -f3)

    if [ "$ACTION" = "off" ]; then
        write_lock "$NODE" "$OFF_VAL"
    else
        write_unlock "$NODE" "$ON_VAL"
    fi
    return 0
}

is_game_running() {
    if [ ! -f "$GAMES_CONF" ]; then
        return 1
    fi
    FG_APP=$(dumpsys window displays 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -n 2)
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        pkg=$(echo "$pkg" | tr -d ' \r\n')
        [ -z "$pkg" ] && continue
        case "$FG_APP" in
            *"$pkg"*) return 0 ;;
        esac
    done < "$GAMES_CONF"
    return 1
}

LAST_STATE="none"
LAST_PLUGGED="-1"
THERMAL_PAUSED=0
NO_SWITCH_NOTIFIED=0

while true; do
    if [ -f "$CONFIG" ]; then
        . "$CONFIG"
    fi

    CAPACITY=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 50)
    RAW_TEMP=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 300)
    TEMP_C=$((RAW_TEMP / 10))

    USB_ONLINE=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
    AC_ONLINE=$(cat /sys/class/power_supply/ac/online 2>/dev/null || echo 0)
    WIRELESS_ONLINE=$(cat /sys/class/power_supply/wireless/online 2>/dev/null || echo 0)

    IS_PLUGGED=0
    if [ "$USB_ONLINE" = "1" ] || [ "$AC_ONLINE" = "1" ] || [ "$WIRELESS_ONLINE" = "1" ]; then
        IS_PLUGGED=1
    fi

    # Charger Plug / Unplug Detection
    if [ "$IS_PLUGGED" != "$LAST_PLUGGED" ]; then
        if [ "$IS_PLUGGED" -eq 1 ]; then
            send_notif "🔌 Charger Connected" "Smart Bypass Charging is monitoring your battery (${CAPACITY}%)."
        elif [ "$LAST_PLUGGED" = "1" ]; then
            if [ "$CHARGE_100_ONCE" = "1" ]; then
                sed -i 's/^CHARGE_100_ONCE=.*/CHARGE_100_ONCE=0/' "$CONFIG"
                CHARGE_100_ONCE=0
            fi
            apply_switch on
            LAST_STATE="charging"
            THERMAL_PAUSED=0
            send_notif "🔋 Charger Disconnected" "Charging controls reset to default (${CAPACITY}%)."
        fi
        LAST_PLUGGED="$IS_PLUGGED"
    fi

    # Thermal Auto-Pause Hystersis (Pause >= 42C, Resume <= 38C)
    if [ "$THERMAL_ENABLE" = "1" ]; then
        if [ "$TEMP_C" -ge 42 ]; then
            THERMAL_PAUSED=1
        elif [ "$TEMP_C" -le 38 ]; then
            THERMAL_PAUSED=0
        fi
    else
        THERMAL_PAUSED=0
    fi

    # Game Auto-Bypass Detection
    GAME_ACTIVE=0
    if [ "$GAME_BYPASS" = "1" ] && [ "$IS_PLUGGED" -eq 1 ]; then
        if is_game_running; then
            GAME_ACTIVE=1
        fi
    fi

    # Determine if charging should be paused
    SHOULD_PAUSE=0
    PAUSE_REASON=""

    if [ "$IS_PLUGGED" -eq 1 ]; then
        if [ "$THERMAL_PAUSED" -eq 1 ]; then
            SHOULD_PAUSE=1
            PAUSE_REASON="thermal"
        elif [ "$FORCE_BYPASS" = "1" ]; then
            SHOULD_PAUSE=1
            PAUSE_REASON="bypass"
        elif [ "$GAME_ACTIVE" -eq 1 ]; then
            SHOULD_PAUSE=1
            PAUSE_REASON="game"
        elif [ "$CHARGE_100_ONCE" = "1" ]; then
            SHOULD_PAUSE=0
        elif [ "$SMART_ENABLE" = "1" ]; then
            if [ "$CAPACITY" -ge "$MAX_LIMIT" ]; then
                SHOULD_PAUSE=1
                PAUSE_REASON="limit"
            elif [ "$CAPACITY" -le "$RESUME_LIMIT" ]; then
                SHOULD_PAUSE=0
            else
                if [ "$LAST_STATE" = "paused" ]; then
                    SHOULD_PAUSE=1
                    PAUSE_REASON="limit"
                fi
            fi
        fi
    fi

    # Charging Speed / Wattage Controller (Only apply when actively charging)
    if [ "$SHOULD_PAUSE" -eq 0 ] && [ "$IS_PLUGGED" -eq 1 ]; then
        CCC_NODE="/sys/class/power_supply/battery/constant_charge_current"
        if [ -f "$CCC_NODE" ]; then
            if [ "$CHARGE_SPEED" = "2000000" ]; then
                write_lock "$CCC_NODE" "2000000"
            elif [ "$CHARGE_SPEED" = "1000000" ]; then
                write_lock "$CCC_NODE" "1000000"
            else
                chmod 0644 "$CCC_NODE" 2>/dev/null
            fi
        fi
    fi

    # Apply Switch State
    if [ "$SHOULD_PAUSE" -eq 1 ]; then
        if apply_switch off; then
            if [ "$LAST_STATE" != "paused" ]; then
                if [ "$PAUSE_REASON" = "thermal" ]; then
                    send_notif "🌡️ Thermal Protection Active" "Battery reached ${TEMP_C}°C. Charging paused until it cools to 38°C."
                elif [ "$PAUSE_REASON" = "bypass" ]; then
                    send_notif "⚡ Bypass Charging Active" "Direct power mode enabled at ${CAPACITY}%. Battery charging is paused."
                elif [ "$PAUSE_REASON" = "game" ]; then
                    send_notif "🎮 Game Bypass Active" "Game detected! Running on direct charger power at ${CAPACITY}%."
                else
                    send_notif "🛡️ Smart Limit Reached (${MAX_LIMIT}%)" "Charging paused at ${CAPACITY}%. Will resume at ${RESUME_LIMIT}%."
                fi
                LAST_STATE="paused"
            fi
        else
            if [ "$NO_SWITCH_NOTIFIED" -eq 0 ]; then
                send_notif "⚠️ Unsupported Kernel" "No compatible charging control switch found on this device."
                NO_SWITCH_NOTIFIED=1
            fi
        fi
    else
        if [ "$IS_PLUGGED" -eq 1 ]; then
            if [ "$LAST_STATE" != "charging" ]; then
                apply_switch on
                if [ "$LAST_STATE" = "paused" ]; then
                    send_notif "🔋 Charging Resumed" "Battery is at ${CAPACITY}% (${TEMP_C}°C). Normal charging restored."
                fi
                LAST_STATE="charging"
            fi
        fi
    fi

    sleep 2
done
