func dorf() {
  docker restart $1 && docker logs -f $1
}
