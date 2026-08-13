# Shared setup for the PageFlip pair harnesses. Source it; it defines write_pair_settings.
#
# Paired reading is a per-device setting and it is OFF by default (docs/pageflip.md section 9 step
# 8), so an instance that is not given one of these files reads solo -- correctly, and silently.
# That is worth stating because it is the failure this file exists to prevent: a pair harness whose
# instances never paired still passes its FIRST screenshot check, since a solo reader on page 0 is
# indistinguishable from a left half on page 0. Every harness therefore also asserts the link came
# up in the role it asked for, which fails at the point the mistake was made.
#
# Role is deliberately not derived from the UDP slot. It is the real setting the device reads, and
# the simulator is the only platform that can test that path.
write_pair_settings() {  # write_pair_settings <left|right> [extra json fields, no braces]
  local side="$1" extra="$2" role=0
  [ "$side" = "right" ] && role=1
  mkdir -p "fs_pf_$side/.crosspoint"
  if [ -n "$extra" ]; then
    printf '{"pageflipEnabled":1,"pageflipRole":%s,%s}\n' "$role" "$extra" >"fs_pf_$side/.crosspoint/settings.json"
  else
    printf '{"pageflipEnabled":1,"pageflipRole":%s}\n' "$role" >"fs_pf_$side/.crosspoint/settings.json"
  fi
}
