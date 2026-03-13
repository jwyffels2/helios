printf "%-12s %-18s %-25s %s\n" "DEVICE" "VENDOR" "MODEL" "SERIAL"
for dev in /dev/ttyUSB* /dev/ttyACM*; do
  [ -e "$dev" ] || continue
  vendor=$(udevadm info -q property -n "$dev" 2>/dev/null | grep '^ID_VENDOR=' | cut -d= -f2-)
  model=$(udevadm info -q property -n "$dev" 2>/dev/null | grep '^ID_MODEL=' | cut -d= -f2-)
  serial=$(udevadm info -q property -n "$dev" 2>/dev/null | grep '^ID_SERIAL=' | cut -d= -f2-)
  printf "%-12s %-18s %-25s %s\n" "$dev" "${vendor:-?}" "${model:-?}" "${serial:-?}"
done
