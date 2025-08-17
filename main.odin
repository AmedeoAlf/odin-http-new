package http

import "core:fmt"
import "core:net"
import "core:strings"

debugger :: proc(r: ^Request) -> bool {
  fmt.println(r)
  return true
}

main :: proc() {
  handlers := []Request_Handler {
    slash_as_index_html,
    debugger,
    resolve_file,
    debugger,
    send_404,
  }
  make_and_run_forever({net.IP4_Address{0, 0, 0, 0}, 3500}, handlers)
}
