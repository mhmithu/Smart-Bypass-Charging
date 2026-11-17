SKIPUNZIP=0

ui_print "=================================="
ui_print "   Smart Bypass Charging v1.1.0   "
ui_print "       Magisk & KernelSU          "
ui_print "=================================="

ui_print "- Setting up configuration files..."

# Create default configuration file
cat <<EOF > "$MODPATH/config.conf"
SMART_ENABLE=1
MAX_LIMIT=90
RESUME_LIMIT=80
FORCE_BYPASS=0
NOTIF_ENABLE=1
CHARGE_SPEED=0
THERMAL_ENABLE=1
CHARGE_100_ONCE=0
GAME_BYPASS=0
EOF

# Create default popular games list for Auto-Bypass
cat <<EOF > "$MODPATH/games.conf"
com.tencent.ig
com.pubg.imobile
com.pubg.newstate
com.dts.freefireth
com.dts.freefiremax
com.activision.callofduty.shooter
com.miHoYo.GenshinImpact
com.mobile.legends
com.ea.gp.fifamobile
EOF

# Set required permissions
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/config.conf 0 0 0644
set_perm $MODPATH/games.conf 0 0 0644

ui_print "- Installation Complete!"
ui_print "- Open WebUI from KernelSU or KSUWebUI to access Settings."
