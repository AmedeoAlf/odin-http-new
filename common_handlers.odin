package http

import "core:fmt"
import "core:net"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

slash_as_index_html: Request_Handler : proc(r: ^Request) -> bool {
  if r.route != "/" do return true

  file, err := os.open("index.html")
  if file == os.INVALID_HANDLE || err != nil do return true
  defer os.close(file)

  send_file(r.from, r, file)

  return false
}

resolve_file: Request_Handler : proc(r: ^Request) -> bool {
  file, err := os.open(r.route[1:])
  if file == os.INVALID_HANDLE || err != nil do return true
  defer os.close(file)

  send_file(r.from, r, file)

  return false
}

send_404: Request_Handler : proc(r: ^Request) -> bool {
  net.send(
    r.from,
    transmute([]u8)string(
      "HTTP/1.1 404 Not Found\r\nContent-type: text/plain\r\n\r\n404 Not Found\r\n",
    ),
  )
  return false
}
