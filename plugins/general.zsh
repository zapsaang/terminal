export LS_OPTINS='--color=auto'

alias ll='ls $LS_OPTINS -ahlF'
alias la='ls $LS_OPTINS -A'
alias ls='ls $LS_OPTINS'
alias l='ls $LS_OPTINS -CF'

alias pip='pip3'
alias python='python3'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

alias sudo='sudo -i'

alias df='df -h'
alias du='du -h'

function bddc() {
    echo "$1" | base64 -Dd | zstd -d -o "$2"
}

function bdsn() {
    echo "$1" | base64 -Dd | snzip -dc > "$2"
}

gen_pass() {
  local input="$1"
  local length="${2:-64}"
  local level="${3:-medium}"

  if [ -z "$input" ]; then
    echo "Error: input is required" >&2
    return 1
  fi

  if ! [[ "$length" =~ ^[0-9]+$ ]] || [ "$length" -le 0 ]; then
    echo "Error: length must be a positive integer" >&2
    return 1
  fi

  local charset=""
  local specials='!@#%^&*()-_=+[]{}:,.?'

  case "$level" in
    low) charset=$(printf "%s" {a..z}) ;;
    medium) charset=$(printf "%s%s%s" {A..Z} {a..z} {0..9}) ;;
    strong) charset=$(printf "%s%s%s%s" {A..Z} {a..z} {0..9} "$specials") ;;
    *) echo "Invalid level: choose low, medium, or strong" >&2; return 1 ;;
  esac

  local hex=$(printf "%s" "$input" | sha512sum | awk '{print $1}')
  local binary=$(printf "%s" "$hex" | sed 's/\([0-9A-F]\{2\}\)/\\x\1/gI' | xargs printf "%b")
  local raw=$(printf "%s" "$binary" | base64)
  local filtered=$(printf "%s" "$raw" | tr -cd "$charset")

  while [ ${#filtered} -lt $length ]; do
    hex=$(printf "%s" "$raw" | sha512sum | awk '{print $1}')
    binary=$(printf "%s" "$hex" | sed 's/\([0-9A-F]\{2\}\)/\\x\1/gI' | xargs printf "%b")
    raw=$(printf "%s" "$binary" | base64)
    filtered="$filtered$(printf "%s" "$raw" | tr -cd "$charset")"
  done

  local password=$(printf "%s" "$filtered" | cut -c1-"${length}")
  local hash=$(printf "%s" "$input" | sha1sum | awk '{print $1}')

  replace_char_at_pos() {
    local str="$1"
    local pos="$2"
    local char="$3"
    local len=${#str}
    
    if [ $pos -ge $len ]; then
      pos=$((len - 1))
    fi
    
    if [ $pos -lt 0 ]; then
      pos=0
    fi
    
    echo "${str:0:$pos}${char}${str:$((pos+1))}"
  }

  if [ "$level" != "low" ]; then
    if ! printf "%s" "$password" | grep -q '[A-Z]'; then
      local pos=$((0x${hash:0:2} % length))
      local sym=$(printf "%s" {A..Z} | cut -c$((0x${hash:2:2} % 26 + 1)))
      password=$(replace_char_at_pos "$password" $pos "$sym")
    fi
    if ! printf "%s" "$password" | grep -q '[a-z]'; then
      local pos=$((0x${hash:4:2} % length))
      local sym=$(printf "%s" {a..z} | cut -c$((0x${hash:6:2} % 26 + 1)))
      password=$(replace_char_at_pos "$password" $pos "$sym")
    fi
    if ! printf "%s" "$password" | grep -q '[0-9]'; then
      local pos=$((0x${hash:8:2} % length))
      local sym=$((0x${hash:10:2} % 10))
      password=$(replace_char_at_pos "$password" $pos "$sym")
    fi
  fi

  if [ "$level" = "strong" ]; then
    if ! printf "%s" "$password" | grep -q "[$specials]"; then
      local pos=$((0x${hash:12:2} % length))
      local idx=$((0x${hash:14:2} % ${#specials}))
      local sym="${specials:$idx:1}"
      password=$(replace_char_at_pos "$password" $pos "$sym")
    fi
  fi

  echo "$password"
}
