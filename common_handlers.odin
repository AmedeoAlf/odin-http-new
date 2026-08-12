package http

import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

slash_as_index_html: Request_Handler : proc(r: ^Request) -> bool {
  if r.route != "" || r.method != .GET do return true

  file, err := os.open("index.html")
  if err != nil do return true
  defer os.close(file)

  send_file(r.from.sock, r, file, "index.html")

  return false
}

resolve_file: Request_Handler : proc(r: ^Request) -> bool {
  if r.method != .GET do return true

  file, err := os.open(r.route)
  if err != nil do return true
  defer os.close(file)

  send_file(r.from.sock, r, file, r.route)

  return false
}

send_404: Request_Handler : proc(r: ^Request) -> bool {
  net.send(
    r.from.sock,
    transmute([]u8)string(
      "HTTP/1.1 404 Not Found\r\n" +
      "Content-type: text/plain\r\n" +
      "\r\n" +
      "404 Not Found\r\n",
    ),
  )
  return false
}

send_directory_listing: Request_Handler : proc(r: ^Request) -> bool {
  if r.route != "" && !os.is_dir(r.route) || r.method != .GET do return true

  dir, err := os.open(r.route if len(r.route) > 1 else ".")
  defer os.close(dir)
  if err != nil do return true

  files, err2 := os.read_dir(dir, 50, context.temp_allocator)
  // defer os.file_info_slice_delete(files)
  defer free_all(context.temp_allocator)
  if err2 != nil do return true

  net.send(
    r.from.sock,
    transmute([]u8)string(
      "HTTP/1.1 200 OK\r\n" +
      "Content-type: text/html\r\n" +
      "\r\n" +
      #load("directory_listing_start.html"),
    ),
  )

  {
    builder := strings.builder_make_none()
    defer strings.builder_destroy(&builder)
    for f in files {
      strings.builder_reset(&builder)
      fmt.sbprintfln(&builder, "      <tr>")

      if f.type == .Directory {
        fmt.sbprintfln(&builder, "        <td>dir</td>")
        fmt.sbprintfln(
          &builder,
          "        <td><a href=\"%s/%s\">%[1]s/</a></td>",
          r.route,
          f.name,
        )
      } else {
        fmt.sbprintfln(&builder, "        <td>%M</td>", f.size)
        fmt.sbprintfln(
          &builder,
          "        <td><a href=\"%s/%s\">%[1]s</a></td>",
          r.route,
          f.name,
        )
      }
      fmt.sbprintfln(&builder, "      </tr>")
      net.send(r.from.sock, builder.buf[:])
    }
  }


  net.send(r.from.sock, #load("directory_listing_end.html"))

  return false
}

upload_file: Request_Handler : proc(r: ^Request) -> bool {
  if r.method != .PUT do return true

  fmt.println("uploaded to '", r.route, "',", "bytes\n")

  return false
}
