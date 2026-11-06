#!/system/bin/sh
MODDIR=${0%/*}
CONFIG_FILE="$MODDIR/config.conf"
SWITCH_CACHE="$MODDIR/active_switch.conf"
BAT_PATH="/sys/class/power_supply/battery"

# Wait until the device has fully booted
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 3
done

# Dynamically read max charge control limit and default constant current
MAX_CCL="1"
if [ -f "$BAT_PATH/charge_control_limit_max" ]; then
    VAL=$(cat "$BAT_PATH/charge_control_limit_max" 2>/dev/null)
    [ -n "$VAL" ] && [ "$VAL" -gt 0 ] 2>/dev/null && MAX_CCL="$VAL"
fi

DEF_CCC="3000000"
if [ -f "$BAT_PATH/constant_charge_current" ]; then
    VAL=$(cat "$BAT_PATH/constant_charge_current" 2>/dev/null)
    [ -n "$VAL" ] && [ "$VAL" -gt 100000 ] 2>/dev/null && DEF_CCC="$VAL"
fi

# Universal Charging Switch Database (Inspired by ACC - Advanced Charging Controller)
# Format: "NODE_PATH|ENABLE_VALUE|DISABLE_VALUE"
# Ordered by priority: True Hardware Bypass / Idle Mode switches first, fallbacks last
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
$BAT_PATH/charge_control_limit|0|$MAX_CCL
$BAT_PATH/constant_charge_current|$DEF_CCC|0
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
    PERM="$3" # 0444 to lock against system override, 0644 to unlock
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
        return 1 # Not charging (0 = true, 1 = false in shell return codes)
    fi

    # Also check current_now for devices that keep status as "Charging" even at 0mA (Idle mode)
    if [ -f "$BAT_PATH/current_now" ]; then
        CURR=$(cat "$BAT_PATH/current_now" 2>/dev/null)
        # Remove negative sign if present
        CURR_ABS=${CURR#-}
        # If current is very low (< 50mA / 50000uA), charging is effectively paused/idle
        if [ -n "$CURR_ABS" ] && [ "$CURR_ABS" -lt 5000 ] 2>/dev/null; then
            return 1 # Not charging
        fi
    fi

    return 0 # Still charging
}

# ACC-style Auto-Detection: Finds and caches the single working switch for this device
find_working_switch() {
    # 1. If we already found and cached a working switch, use it
    if [ -f "$SWITCH_CACHE" ]; then
        CACHED=$(cat "$SWITCH_CACHE" 2>/dev/null)
        NODE=$(echo "$CACHED" | cut -d'|' -f1)
        if [ -f "$NODE" ]; then
            echo "$CACHED"
            return 0
        fi
    fi

    # 2. Probe switches one by one to see which one actually stops charging
    for entry in $SWITCH_LIST; do
        [ -z "$entry" ] && continue
        NODE=$(echo "$entry" | cut -d'|' -f1)
        EN_VAL=$(echo "$entry" | cut -d'|' -f2)
        DIS_VAL=$(echo "$entry" | cut -d'|' -f3)

        if [ -f "$NODE" ]; then
            # Refresh dynamic default current if testing constant_charge_current
            if [ "$NODE" = "$BAT_PATH/constant_charge_current" ]; then
                CURR_CCC=$(cat "$NODE" 2>/dev/null)
                [ -n "$CURR_CCC" ] && [ "$CURR_CCC" -gt 100000 ] 2>/dev/null && EN_VAL="$CURR_CCC"
            fi

            # Apply disable value and wait 2 seconds to test effect
            write_node "$NODE" "$DIS_VAL" "0444"
            sleep 2

            if ! is_currently_charging; then
                # Success! This switch works on this device. Cache it.
                WORKING_ENTRY="$NODE|$EN_VAL|$DIS_VAL"
                echo "$WORKING_ENTRY" > "$SWITCH_CACHE"
                echo "$WORKING_ENTRY"
                return 0
            else
                # Did not work, revert this switch before testing the next one
                write_node "$NODE" "$EN_VAL" "0644"
            fi
        fi
    done

    return 1
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

# Function to re-enable normal charging
enable_charging() {
    if [ -f "$SWITCH_CACHE" ]; then
        ACTIVE_SW=$(cat "$SWITCH_CACHE" 2>/dev/null)
        NODE=$(echo "$ACTIVE_SW" | cut -d'|' -f1)
        EN_VAL=$(echo "$ACTIVE_SW" | cut -d'|' -f2)
        write_node "$NODE" "$EN_VAL" "0644"
    else
        # Fallback: reset all existing switches to enabled state
        for entry in $SWITCH_LIST; do
            [ -z "$entry" ] && continue
            NODE=$(echo "$entry" | cut -d'|' -f1)
            EN_VAL=$(echo "$entry" | cut -d'|' -f2)
            [ -f "$NODE" ] && write_node "$NODE" "$EN_VAL" "0644"
        done
    fi
}

# Universal function to check if charger is physically plugged in
is_charger_connected() {
    # Check all possible power supply online/present/voltage nodes
    for psy in /sys/class/power_supply/*; do
        TYPE=$(cat "$psy/type" 2>/dev/null)
        # Skip battery and BMS nodes, check only power sources (USB, Mains, Wireless, etc.)
        if [ "$TYPE" != "Battery" ] && [ "$TYPE" != "BMS" ] && [ -n "$TYPE" ]; then
            ONLINE=$(cat "$psy/online" 2>/dev/null)
            PRESENT=$(cat "$psy/present" 2>/dev/null)
            VOLT=$(cat "$psy/voltage_now" 2>/dev/null)

            if [ "$ONLINE" = "1" ] || [ "$PRESENT" = "1" ]; then
                echo 1
                return
            fi
            # If source voltage is > 3.5V (3500000 uV or 3500 mV), charger is plugged in
            if [ -n "$VOLT" ] && [ "$VOLT" -gt 3500000 ] 2>/dev/null; then
                echo 1
                return
            fi
        fi
    done

    # Also check battery status: if it says Charging, Not charging, or Full, cable is attached
    BAT_STAT=$(cat "$BAT_PATH/status" 2>/dev/null)
    if [ "$BAT_STAT" = "Charging" ] || [ "$BAT_STAT" = "Not charging" ] || [ "$BAT_STAT" = "Full" ]; then
        echo 1
        return
    fi

    echo 0
}

# Clean up any old switch cache on fresh boot and ensure charging is enabled initially
rm -f "$SWITCH_CACHE" 2>/dev/null

# State tracking variables
PREV_PLUGGED=0
CURRENT_STATE="normal" # States: normal, bypass, limit_reached
TEMP_WARNED=0
UNPLUG_DEBOUNCE=0

# Main monitoring loop
while true; do
    # Read user configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        SMART_ENABLE=1; MAX_LIMIT=80; RESUME_LIMIT=75; FORCE_BYPASS=0; NOTIF_ENABLE=1
    fi

    CAPACITY=$(cat "$BAT_PATH/capacity" 2>/dev/null)
    TEMP_RAW=$(cat "$BAT_PATH/temp" 2>/dev/null)
    TEMP_C=$((TEMP_RAW / 10))
    PLUGGED=$(is_charger_connected)

    # 1. Overheating Warning Check (Triggers at >= 42°C, resets at <= 39°C)
    if [ "$TEMP_C" -ge 42 ] && [ "$TEMP_WARNED" -eq 0 ]; then
        send_notif "⚠️ Overheating Warning!" "Battery temperature is ${TEMP_C}°C! Please pause gaming or unplug charger." "TempTag"
        TEMP_WARNED=1
    elif [ "$TEMP_C" -le 39 ] && [ "$TEMP_WARNED" -eq 1 ]; then
        TEMP_WARNED=0
    fi

    # 2. Charger Connect / Disconnect Detection
    if [ "$PLUGGED" -eq 1 ]; then
        UNPLUG_DEBOUNCE=0
        if [ "$PREV_PLUGGED" -eq 0 ]; then
            send_notif "⚡ Charger Connected" "Battery at ${CAPACITY}%. Smart Bypass Monitoring is active." "PlugTag"
            PREV_PLUGGED=1
            CURRENT_STATE="normal"
        fi
    else
        if [ "$PREV_PLUGGED" -eq 1 ]; then
            # Wait 3 consecutive checks (6 seconds) to confirm physical cable unplug
            UNPLUG_DEBOUNCE=$((UNPLUG_DEBOUNCE + 1))
            if [ "$UNPLUG_DEBOUNCE" -ge 3 ]; then
                send_notif "🔌 Charger Disconnected" "Unplugged at ${CAPACITY}%. Charging switches reset to default." "PlugTag"
                enable_charging
                PREV_PLUGGED=0
                CURRENT_STATE="normal"
                UNPLUG_DEBOUNCE=0
            fi
        fi
    fi

    # 3. Charging & Bypass Control Logic (When charger is connected)
    if [ "$PREV_PLUGGED" -eq 1 ]; then
        
        # A. Force Bypass Mode for Gaming
        if [ "$FORCE_BYPASS" -eq 1 ]; then
            disable_charging
            if [ "$CURRENT_STATE" != "bypass" ]; then
                send_notif "🔥 Bypass Mode Activated" "Charging stopped at ${CAPACITY}%. Running directly on AC power for gaming!" "StateTag"
                CURRENT_STATE="bypass"
            fi
        
        # B. Smart Charging Mode
        elif [ "$SMART_ENABLE" -eq 1 ]; then
            # If user just turned off Force Bypass and battery is below Max Limit, resume charging
            if [ "$CURRENT_STATE" = "bypass" ] && [ "$CAPACITY" -lt "$MAX_LIMIT" ]; then
                enable_charging
                send_notif "⚡ Normal Charging Resumed" "Bypass mode turned off. Charging battery..." "StateTag"
                CURRENT_STATE="normal"
            fi

            # Stop charging when Max Limit is reached
            if [ "$CAPACITY" -ge "$MAX_LIMIT" ]; then
                disable_charging
                if [ "$CURRENT_STATE" != "limit_reached" ]; then
                    send_notif "🛡️ Smart Limit Reached (${MAX_LIMIT}%)" "Charging stopped to protect battery health. Switched to Bypass/Idle power." "StateTag"
                    CURRENT_STATE="limit_reached"
                fi
            # Resume charging ONLY when battery drops to or below Resume Limit
            elif [ "$CAPACITY" -le "$RESUME_LIMIT" ] && [ "$CURRENT_STATE" = "limit_reached" ]; then
                enable_charging
                send_notif "🔄 Charging Resumed" "Battery dropped to ${CAPACITY}%. Recharging up to ${MAX_LIMIT}%." "StateTag"
                CURRENT_STATE="normal"
            fi

        # C. Standard Charging (When both Force Bypass and Smart Charging are OFF)
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