#!/bin/zsh
# Auto configure zsh proxy env based on system preferences

# Function to set proxy environment variables
set_proxy() {
  local type=$1
  local protocol=$2
  local server=$3
  local port=$4
  export "${type}_proxy=${protocol}://${server}:${port}"
  export "${(U)type}_PROXY=${protocol}://${server}:${port}"
}

function configure_proxy() {
  # Cache the output of scutil --proxy
  scutil_proxy=$(scutil --proxy)

  # Patterns to match the status
  http_enabled_pattern="HTTPEnable : 1"
  https_enabled_pattern="HTTPSEnable : 1"
  ftp_enabled_pattern="FTPEnable : 1"
  socks_enabled_pattern="SOCKSEnable : 1"

  http_enabled=$scutil_proxy[(I)$http_enabled_pattern]
  https_enabled=$scutil_proxy[(I)$https_enabled_pattern]
  ftp_enabled=$scutil_proxy[(I)$ftp_enabled_pattern]
  socks_enabled=$scutil_proxy[(I)$socks_enabled_pattern]

  # http proxy
  if (( http_enabled )); then
    http_server=${${scutil_proxy#*HTTPProxy : }[(f)1]}
    http_port=${${scutil_proxy#*HTTPPort : }[(f)1]}
    set_proxy "http" "http" $http_server $http_port
  fi

  # https proxy
  if (( https_enabled )); then
    https_server=${${scutil_proxy#*HTTPSProxy : }[(f)1]}
    https_port=${${scutil_proxy#*HTTPSPort : }[(f)1]}
    set_proxy "https" "http" $https_server $https_port
  fi

  # ftp proxy
  if (( ftp_enabled )); then
    ftp_server=${${scutil_proxy#*FTPProxy : }[(f)1]}
    ftp_port=${${scutil_proxy#*FTPPort : }[(f)1]}
    set_proxy "ftp" "http" $ftp_server $ftp_port
  fi

  # all_proxy (SOCKS or fallback to http)
  if (( socks_enabled )); then
    socks_server=${${scutil_proxy#*SOCKSProxy : }[(f)1]}
    socks_port=${${scutil_proxy#*SOCKSPort : }[(f)1]}
    set_proxy "all" "socks5" $socks_server $socks_port
    export SOCKS5_SERVER="$socks_server"
    export SOCKS5_PORT="$socks_port"
  elif (( http_enabled )); then
    export all_proxy="$http_proxy"
    export ALL_PROXY="$http_proxy"
  fi
}

function unset_proxy() {
  unset https_proxy
  unset http_proxy
  unset all_proxy
  unset HTTPS_PROXY
  unset HTTP_PROXY
  unset ALL_PROXY

  echo "Proxy settings unset."
}

function show_proxy() {
  # Print the set proxy environment variables for testing
  echo "http_proxy: $http_proxy"
  echo "HTTP_PROXY: $HTTP_PROXY"
  echo "https_proxy: $https_proxy"
  echo "HTTPS_PROXY: $https_proxy"
  echo "ftp_proxy: $ftp_proxy"
  echo "FTP_PROXY: $ftp_proxy"
  echo "all_proxy: $all_proxy"
  echo "ALL_PROXY: $all_proxy"
}

# Aliases
alias proxy="configure_proxy"
alias unproxy="unset_proxy"

# Call the configure_proxy function to automatically configure proxy based on system settings
configure_proxy
