function path_prepend() {
  [ -z "$1" ] && return

  case ":$PATH:" in
    ":$1:"*) return ;;
    *":$1:"*)
      local new_path=
      local IFS=:
      for p in $PATH; do
        [ "$p" = "$1" ] && continue
        new_path="${new_path:+$new_path:}$p"
      done
      PATH="$1:$new_path"
      ;;
    *)
      PATH="$1${PATH:+:$PATH}"
      ;;
  esac
}

function path_append() {
  [ -z "$1" ] && return

  case ":$PATH:" in
    *":$1:"*) return ;;
    *)
      PATH="${PATH:+$PATH:}$1"
      ;;
  esac
}
