package http

import "core:net"

main :: proc() {
  load_mime_types_from_csv(#load("filetypes.csv"))
  make_and_run_forever(
    {net.IP4_Address{0, 0, 0, 0}, 3500},
    {slash_as_index_html, send_directory_listing, resolve_file, send_404},
  )
}
