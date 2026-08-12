package http

import "core:fmt"
import "core:net"

main :: proc() {
  addr := net.Endpoint{net.IP4_Address{0, 0, 0, 0}, 3500}
  fmt.println("Serving on http://", net.endpoint_to_string(addr), sep = "")

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
