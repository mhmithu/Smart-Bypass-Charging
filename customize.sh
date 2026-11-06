SKIPUNZIP=0

ui_print "=================================="
ui_print "     Smart Bypass Charging        "
ui_print "      Magisk & KernelSU           "
ui_print "=================================="

ui_print "- Creating internal configuration..."

# Create default config file inside module directory
cat <<EOF > "$MODPATH/config.conf"
SMART_ENABLE=1
MAX_LIMIT=90
RESUME_LIMIT=80
FORCE_BYPASS=0
NOTIF_ENABLE=1
EOF

# Set required permissions
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/config.conf 0 0 0644

ui_print "- Installation Complete!"
ui_print "- Use KernelSU Manager or KSUWebUI app to access Settings."