#!/system/bin/sh
MODDIR=${0%/*}
CONFIG_FILE="$MODDIR/config.conf"
GAMES_FILE="$MODDIR/games.conf"
SWITCH_CACHE="$MODDIR/active_switch.conf"
BAT_PATH="/sys/class/power_supply/battery"

# Wait until the device has fully booted
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 3
done

# Dynamically determine maximum charge control limit
MAX_CCL="1"
if [ -f "$BAT_PATH/charge_control_limit_max" ]; then
    VAL=$(cat "$BAT_PATH/charge_control_limit_max" 2>/dev/null)
    [ -n "$VAL" ] && [ "$VAL" -gt 0 ] 2>/dev/null && MAX_CCL="$VAL"
fi

# Set high default fast-charging ceiling (12000000 uA = 12A) so fast charging is never capped at 14W (3A)
DEF_CCC="12000000"
if [ -f "$BAT_PATH/constant_charge_current_max" ]; then
    VAL=$(cat "$BAT_PATH/constant_charge_current_max" 2>/dev/null)
    [ -n "$VAL" ] && [ "$VAL" -gt 3000000 ] 2>/dev/null && DEF_CCC="$VAL"
fi

# Universal Charging Switch Database
# Note: constant_charge_current is placed BEFORE charge_control_limit to prevent thermal throttling interference
SWITCH_LIST="
/sys/devices/platform/charger/bypass_charger|0|1
/proc/mtk_battery_cmd/current_cmd|0 0|0 1
$BAT_PATH/charging_enabled|1|0
$BAT_PATH/battery_charging_enabled|1|0
$BAT_PATH/charge_disable|0|1
$BAT_PATH/mmi_charging_enable|1|0
/sys/class/oplus_chg/battery/mmi_charging_enable|1|0
/sys/class/oplus_chg/battery/bcc_current|1|0
$BAT_PATH/op_disable_charge|0|1
/sys/devices/platform/charger/charging_enabled|1|0
/sys/devices/platform/mt-battery/disable_charger|0|1
$BAT_PATH/chg_enable|1|0
$BAT_PATH/enable_charging|1|0
$BAT_PATH/achg_enable|1|0
$BAT_PATH/boot_completed_charging_enabled|1|0
$BAT_PATH/enable_stop_charging|0|1
$BAT_PATH/lrc_enable|0|1
$BAT_PATH/store_mode|0|1
$BAT_PATH/batt_slate_mode|0|1
$BAT_PATH/constant_charge_current|$DEF_CCC|0
$BAT_PATH/charge_control_limit|0|$MAX_CCL
$BAT_PATH/input_suspend|0|1
/sys/class/qcom-battery/input_suspend|0|1
$BAT_PATH/charging_suspend|0|1
/sys/class/hw_power/charger/charge_data/enable_charger|1|0
"

# Function to send Android system notifications
send_notif() {
    if [ "$NOTIF_ENABLE" -eq 1 ]; then
        TITLE="$1"
        MSG="$2"
        TAG="$3"
        su -lp 2000 -c "cmd notification post -S bigtext -t '$TITLE' '$TAG' '$MSG'" >/dev/null 2>&1
    fi
}

# Helper function to write value to a kernel node and lock/unlock permissions
write_node() {
    NODE="$1"
    VAL="$2"
    PERM="$3"
    if [ -f "$NODE" ]; then
        chmod 0644 "$NODE" 2>/dev/null
        echo "$VAL" > "$NODE" 2>/dev/null
        chmod "$PERM" "$NODE" 2>/dev/null
    fi
}

# Function to check if battery is actually charging right now
is_currently_charging() {
    STAT=$(cat "$BAT_PATH/status" 2>/dev/null)
    if [ "$STAT" = "Not charging" ] || [ "$STAT" = "Full" ] || [ "$STAT" = "Discharging" ]; then
        return 1
    fi

    if [ -f "$BAT_PATH/current_now" ]; then
        CURR=$(cat "$BAT_PATH/current_now" 2>/dev/null)
        CURR_ABS=${CURR#-}
        if [ -n "$CURR_ABS" ] && [ "$CURR_ABS" -lt 5000 ] 2>/dev/null; then
            return 1
        fi
    fi

    return 0
}

# ACC-style Auto-Detection: Finds and caches the single working switch for this device
find_working_switch() {
    if [ -f "$SWITCH_CACHE" ]; then
        CACHED=$(cat "$SWITCH_CACHE" 2>/dev/null)
        NODE=$(echo "$CACHED" | cut -d'|' -f1)
        if [ -f "$NODE" ]; then
            echo "$CACHED"
            return 0
        fi
    fi

    for entry in $SWITCH_LIST; do
        [ -z "$entry" ] && continue
        NODE=$(echo "$entry" | cut -d'|' -f1)
        EN_VAL=$(echo "$entry" | cut -d'|' -f2)
        DIS_VAL=$(echo "$entry" | cut -d'|' -f3)

        if [ -f "$NODE" ]; then
            if [ "$NODE" = "$BAT_PATH/constant_charge_current" ]; then
                CURR_CCC=$(cat "$NODE" 2>/dev/null)
                if [ -n "$CURR_CCC" ] && [ "$CURR_CCC" -gt "$DEF_CCC" ] 2>/dev/null; then
                    EN_VAL="$CURR_CCC"
                else
                    EN_VAL="$DEF_CCC"
                fi
            fi

            write_node "$NODE" "$DIS_VAL" "0444"
            sleep 2

            if ! is_currently_charging; then
                WORKING_ENTRY="$NODE|$EN_VAL|$DIS_VAL"
                echo "$WORKING_ENTRY" > "$SWITCH_CACHE"
                echo "$WORKING_ENTRY"
                return 0
            else
                write_node "$NODE" "$EN_VAL" "0644"
            fi
        fi
    done

    return 1
}

# Function to apply user-selected charging speed (Fast, Balanced 2000mA, or Cool Night 1000mA)
apply_charging_speed() {
    if [ -f "$BAT_PATH/constant_charge_current" ]; then
        if [ -n "$CHARGE_SPEED" ] && [ "$CHARGE_SPEED" -gt 0 ] 2>/dev/null; then
            # Lock to user-selected current limit (e.g., 2000000 uA or 1000000 uA)
            write_node "$BAT_PATH/constant_charge_current" "$CHARGE_SPEED" "0444"
        else
            # Unlock and set high ceiling so hardware PD/fast charging runs at full wattage
            write_node "$BAT_PATH/constant_charge_current" "$DEF_CCC" "0644"
        fi
    fi
}

# Function to disable charging using ONLY the verified working switch
disable_charging() {
    ACTIVE_SW=$(find_working_switch)
    if [ -n "$ACTIVE_SW" ]; then
        NODE=$(echo "$ACTIVE_SW" | cut -d'|' -f1)
        DIS_VAL=$(echo "$ACTIVE_SW" | cut -d'|' -f3)
        write_node "$NODE" "$DIS_VAL" "0444"
    fi
}

# Function to re-enable charging and apply speed profile
enable_charging() {
    if [ -f "$SWITCH_CACHE" ]; then
        ACTIVE_SW=$(cat "$SWITCH_CACHE" 2>/dev/null)
        NODE=$(echo "$ACTIVE_SW" | cut -d'|' -f1)
        EN_VAL=$(echo "$ACTIVE_SW" | cut -d'|' -f2)
        write_node "$NODE" "$EN_VAL" "0644"
    else
        for entry in $SWITCH_LIST; do
            [ -z "$entry" ] && continue
            NODE=$(echo "$entry" | cut -d'|' -f1)
            EN_VAL=$(echo "$entry" | cut -d'|' -f2)
            [ -f "$NODE" ] && write_node "$NODE" "$EN_VAL" "0644"
        done
    fi
    # Ensure thermal charge_control_limit is unlocked and set to 0
    [ -f "$BAT_PATH/charge_control_limit" ] && write_node "$BAT_PATH/charge_control_limit" "0" "0644"
    # Apply charging speed limit (if any)
    apply_charging_speed
}

# Universal function to check if charger is physically plugged in
is_charger_connected() {
    for psy in /sys/class/power_supply/*; do
        TYPE=$(cat "$psy/type" 2>/dev/null)
        if [ "$TYPE" != "Battery" ] && [ "$TYPE" != "BMS" ] && [ -n "$TYPE" ]; then
            ONLINE=$(cat "$psy/online" 2>/dev/null)
            PRESENT=$(cat "$psy/present" 2>/dev/null)
            VOLT=$(cat "$psy/voltage_now" 2>/dev/null)

            if [ "$ONLINE" = "1" ] || [ "$PRESENT" = "1" ]; then
                echo 1
                return
            fi
            if [ -n "$VOLT" ] && [ "$VOLT" -gt 3500000 ] 2>/dev/null; then
                echo 1
                return
            fi
        fi
    done

    BAT_STAT=$(cat "$BAT_PATH/status" 2>/dev/null)
    if [ "$BAT_STAT" = "Charging" ] || [ "$BAT_STAT" = "Not charging" ] || [ "$BAT_STAT" = "Full" ]; then
        echo 1
        return
    fi

    echo 0
}

# Function to check if a configured game is currently in the foreground
is_game_running() {
    [ "$GAME_BYPASS" != "1" ] && return 1
    [ ! -f "$GAMES_FILE" ] && return 1

    # Retrieve foreground package name only when screen is awake
    FG_APP=$(dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | grep -oE '[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+' | head -n 1)
    [ -z "$FG_APP" ] && return 1

    if grep -Fxq "$FG_APP" "$GAMES_FILE" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Clean up old switch cache on boot and restore full fast-charging ceiling
rm -f "$SWITCH_CACHE" 2>/dev/null
CHARGE_SPEED=0
enable_charging

# State tracking variables
PREV_PLUGGED=0
CURRENT_STATE="normal" # normal, bypass, game_bypass, limit_reached, full_once, thermal_pause
THERMAL_PAUSED=0
UNPLUG_DEBOUNCE=0
LAST_SPEED="0"

# Main monitoring loop
while true; do
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        SMART_ENABLE=1; MAX_LIMIT=90; RESUME_LIMIT=80; FORCE_BYPASS=0
        NOTIF_ENABLE=1; CHARGE_SPEED=0; THERMAL_ENABLE=1; CHARGE_100_ONCE=0; GAME_BYPASS=0
    fi

    CAPACITY=$(cat "$BAT_PATH/capacity" 2>/dev/null)
    TEMP_RAW=$(cat "$BAT_PATH/temp" 2>/dev/null)
    TEMP_C=$((TEMP_RAW / 10))
    PLUGGED=$(is_charger_connected)

    # 1. Charger Connect / Disconnect Detection
    if [ "$PLUGGED" -eq 1 ]; then
        UNPLUG_DEBOUNCE=0
        if [ "$PREV_PLUGGED" -eq 0 ]; then
            send_notif "⚡ Charger Connected" "Battery at ${CAPACITY}% (${TEMP_C}°C). Smart Bypass Monitoring active." "PlugTag"
            PREV_PLUGGED=1
            CURRENT_STATE="normal"
            LAST_SPEED="$CHARGE_SPEED"
            apply_charging_speed
        fi
    else
        if [ "$PREV_PLUGGED" -eq 1 ]; then
            UNPLUG_DEBOUNCE=$((UNPLUG_DEBOUNCE + 1))
            if [ "$UNPLUG_DEBOUNCE" -ge 3 ]; then
                # Reset Charge to 100% Once flag upon unplugging
                if [ "$CHARGE_100_ONCE" = "1" ]; then
                    sed -i 's/CHARGE_100_ONCE=1/CHARGE_100_ONCE=0/g' "$CONFIG_FILE" 2>/dev/null
                fi
                CHARGE_SPEED=0
                enable_charging
                send_notif "🔌 Charger Disconnected" "Unplugged at ${CAPACITY}%. Fast charging ceiling restored." "PlugTag"
                PREV_PLUGGED=0
                CURRENT_STATE="normal"
                THERMAL_PAUSED=0
                UNPLUG_DEBOUNCE=0
            fi
        fi
    fi

    # 2. Charging, Thermal, Speed & Bypass Logic (When charger is connected)
    if [ "$PREV_PLUGGED" -eq 1 ]; then

        # Apply new charging speed immediately if changed by user during normal charging
        if [ "$CHARGE_SPEED" != "$LAST_SPEED" ]; then
            LAST_SPEED="$CHARGE_SPEED"
            if [ "$CURRENT_STATE" = "normal" ]; then
                apply_charging_speed
            fi
        fi

        # Priority A: Smart Thermal Protection (Pause >= 42°C, Resume <= 38°C)
        if [ "$THERMAL_ENABLE" -eq 1 ] && [ "$TEMP_C" -ge 42 ]; then
            disable_charging
            if [ "$THERMAL_PAUSED" -eq 0 ]; then
                send_notif "🌡️ Thermal Protection Active!" "Battery reached ${TEMP_C}°C. Charging paused until it cools down to 38°C." "StateTag"
                THERMAL_PAUSED=1
                CURRENT_STATE="thermal_pause"
            fi
        elif [ "$THERMAL_PAUSED" -eq 1 ]; then
            if [ "$TEMP_C" -le 38 ]; then
                THERMAL_PAUSED=0
                enable_charging
                send_notif "❄️ Battery Cooled Down (${TEMP_C}°C)" "Safe temperature restored. Resuming normal operation." "StateTag"
                CURRENT_STATE="normal"
            else
                disable_charging
            fi

        # Priority B: Manual Force Bypass Mode
        elif [ "$FORCE_BYPASS" -eq 1 ]; then
            disable_charging
            if [ "$CURRENT_STATE" != "bypass" ]; then
                send_notif "🔥 Bypass Mode Activated" "Charging stopped at ${CAPACITY}%. Running directly on AC power!" "StateTag"
                CURRENT_STATE="bypass"
            fi

        # Priority C: Auto-Bypass on Gaming
        elif is_game_running; then
            disable_charging
            if [ "$CURRENT_STATE" != "game_bypass" ]; then
                send_notif "🎮 Game Detected: Bypass Active" "Paused charging at ${CAPACITY}% to prevent heat during gaming." "StateTag"
                CURRENT_STATE="game_bypass"
            fi

        # Priority D: Charge to 100% Once Override
        elif [ "$CHARGE_100_ONCE" -eq 1 ]; then
            if [ "$CAPACITY" -ge 100 ]; then
                disable_charging
                if [ "$CURRENT_STATE" != "full_once" ]; then
                    send_notif "🔋 100% Full Charge Reached" "One-time 100% charge complete. Switched to Idle power." "StateTag"
                    CURRENT_STATE="full_once"
                fi
            else
                if [ "$CURRENT_STATE" != "normal" ]; then
                    enable_charging
                    CURRENT_STATE="normal"
                fi
            fi

        # Priority E: Smart Charging Mode
        elif [ "$SMART_ENABLE" -eq 1 ]; then
            if { [ "$CURRENT_STATE" = "bypass" ] || [ "$CURRENT_STATE" = "game_bypass" ]; } && [ "$CAPACITY" -lt "$MAX_LIMIT" ]; then
                enable_charging
                send_notif "⚡ Normal Charging Resumed" "Bypass mode ended. Charging battery..." "StateTag"
                CURRENT_STATE="normal"
            fi

            if [ "$CAPACITY" -ge "$MAX_LIMIT" ]; then
                disable_charging
                if [ "$CURRENT_STATE" != "limit_reached" ]; then
                    send_notif "🛡️ Smart Limit Reached (${MAX_LIMIT}%)" "Charging stopped to protect battery health. Switched to Bypass/Idle power." "StateTag"
                    CURRENT_STATE="limit_reached"
                fi
            elif [ "$CAPACITY" -le "$RESUME_LIMIT" ] && [ "$CURRENT_STATE" = "limit_reached" ]; then
                enable_charging
                send_notif "🔄 Charging Resumed" "Battery dropped to ${CAPACITY}%. Recharging up to ${MAX_LIMIT}%." "StateTag"
                CURRENT_STATE="normal"
            fi

        # Priority F: Standard Charging
        else
            if [ "$CURRENT_STATE" != "normal" ]; then
                enable_charging
                send_notif "⚡ Standard Charging" "All smart limits disabled. Charging normally." "StateTag"
                CURRENT_STATE="normal"
            fi
        fi
    fi

    sleep 2
done
