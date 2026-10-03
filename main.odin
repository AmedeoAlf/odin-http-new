package http

import "core:fmt"
import "core:net"

main :: proc() {
  addr := net.Endpoint{net.IP4_Address{0, 0, 0, 0}, 3500}
  for ip in get_ips() {
    fmt.printfln("Serving on http://{}:3500 ({})", ip.addr, ip.ifname)
  }
  free_all(context.temp_allocator)

  load_mime_types_from_csv(#load("filetypes.csv"))
  make_and_run_forever(
    addr,
    {
      slash_as_index_html,
      upload_file,
      send_directory_listing,
      resolve_file,
      send_404,
    },
  )
}
