parse() {
  [ -z "$1" ] && { echo "empty" >&2; return 1; }
  trap 'cleanup' ERR
  set -e
  value=$(( $1 + 3 )) || exit 1
}
