#!/bin/bash -eu
#
# Script to upgrade Alex's router.  The manufacturer suggested upgrading through
# the sequence of versions without skipping any, which can be time consuming.

usage="$0 router_address"

firmwares=(
  https://dl.ui.com/unifi/firmware/U2Sv2/3.9.54.9373/BZ.qca9342.v3.9.54.9373.180913.2356.bin
  https://dl.ui.com/unifi/firmware/U2Sv2/4.0.9.9636/BZ.qca9342.v4.0.9.9636.181128.2215.bin
  https://dl.ui.com/unifi/firmware/U2Sv2/4.0.10.9653/BZ.qca9342.v4.0.10.9653.181205.1310.bin
  https://dl.ui.com/unifi/firmware/U2Sv2/4.0.14.9736/BZ.qca9342.v4.0.14.9736.181224.1724.bin
  https://dl.ui.com/unifi/firmware/U2Sv2/4.0.15.9872/BZ.qca9342.v4.0.15.9872.181229.0259.bin
  https://dl.ui.com/unifi/firmware/U2Sv2/4.0.42.10433/BZ.qca9342.v4.0.42.10433.190518.0923.bin
  https://dl.ui.com/unifi/firmware/U2Sv2/4.0.54.10625/BZ.qca9342.v4.0.54.10625.190801.1544.bin
  https://dl.ui.com/unifi/firmware/U2Sv2/4.0.66.10832/BZ.qca9342.v4.0.66.10832.191023.1948.bin
  https://dl.ui.com/unifi/firmware/U2Sv2/4.0.69.10871/BZ.qca9342.v4.0.69.10871.191109.0532.bin
  https://dl.ui.com/unifi/firmware/U2Sv2/4.0.80.10875/BZ.qca9342.v4.0.80.10875.200111.2335.bin
)

main() {
  router_address="${1:? "$usage"}"

  initial_version=$(get_current_version "$router_address")
  [[ $? -eq 0 ]] || return 1

  echo "Current version on router: '$initial_version'"

  target_version_is_older=true
  for url in "${firmwares[@]}"; do
    # Skip past older versions and the current version.
    target_version=$(get_version_from_url "$url")
    if $target_version_is_older; then
      if [[ "$target_version" == "$initial_version" ]]; then
        echo "Found current version's firmware, upgrading sequentially from next version."
        target_version_is_older=false
      else
        echo "Skipping older version: '$target_version'"
      fi
      continue
    fi

    update_router "$router_address" "$url" || {
      break
    }
  done

  if $target_version_is_older; then
    echo "Initial router version unknown, maybe too old: '$initial_version'"
    exit 1
  fi

  echo "Successfully updated to most recent version."
}

update_router() {
  router_address="${1:?}"
  url="${2:?}"

  target_version="$(get_version_from_url "$url")"

  echo "Starting update to $target_version"

  echo "Downloading $url"
  run_on_router "$router_address" curl "$url" -o /tmp/fwupdate.bin || {
    echo "Failure downloading: exit_code=$?"
    return 1
  } 

  echo "Starting on router update process..."
  run_on_router "$router_address" "touch uphelp; chmod +x uphelp; cat > uphelp" <<'EOF'
#!/bin/sh

trap '' HUP INT QUIT ABRT PIPE TERM
echo trapping | tee FUCK
sleep 3
echo fuckthefuckingfuckers >> FUCK
nohup syswrapper.sh upgrade2
EOF

  run_on_router_tty "$router_address" 'nohup ~/uphelp & sleep 1; exit 0' || {
    echo "Failure starting background update process on router" >&2
    return 1
  }

  for ((i=0; i < 600; i=i+1)); do
    echo -n "  checking update status: "
    current_version=$(
        get_current_version "$router_address" || \
            echo "version fetch not yet successful")
    if [[ "$current_version" == "$target_version" ]]; then
      echo "update successful."
      aplay /tmp/foo.sound
      # The router seems to need time to set itself up.  curl errors with SSL
      # problems if we try too soon.
      sleep 10
      return 0
    fi
    echo "not done yet: current_version=$current_version"
    sleep 2
  done

  echo "Upgrade failed."

  return 1
}

get_version_from_url() {
  echo ${1:?} | awk -F/ '{print $7}'
}

get_current_version() {
  router_address="${1:?}"
  info=$(run_on_router "$router_address" mca-cli-op info)
  if [[ $? -ne 0 ]]; then
    echo "Error connecting to router." >&2
    return 1
  fi

  if ! echo "$info" | awk ' /^Version: / { print $2 }'; then
    echo "Invalid info response from router."
    return 1
  fi

  return 0
}

run_on_router() {
  router_address="${1:?}"
  shift
  sshpass -p ubnt ssh -T -o ConnectTimeout=2 "ubnt@$router_address" "$@"
}

run_on_router_tty() {
  router_address="${1:?}"
  shift
  sshpass -p ubnt ssh -t -o ConnectTimeout=2 "ubnt@$router_address" "$@"
}

main "$@"
