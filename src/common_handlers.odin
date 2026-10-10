package http

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:sys/linux"
import "tcp_reader"

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

  files, err2 := os.read_all_directory(dir, context.temp_allocator)
  // defer os.file_info_slice_delete(files)
  defer free_all(context.temp_allocator)
  if err2 != nil do return true

  net.send(
    r.from.sock,
    transmute([]u8)string(
      "HTTP/1.1 200 OK\r\n" +
      "Content-type: text/html\r\n" +
      "\r\n" +
      #load("../build/directory_listing_start.html"),
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
          "        <td><a href=\"/%s/%s\">%[1]s</a></td>",
          r.route,
          f.name,
        )
      }
      fmt.sbprintfln(&builder, "      </tr>")
      net.send(r.from.sock, builder.buf[:])
    }
  }


  net.send(r.from.sock, #load("../build/directory_listing_end.html"))

  return false
}

upload_file: Request_Handler : proc(r: ^Request) -> bool {
  if r.method != .PUT do return true

  filename := r.route if r.route != "" else "upload"

  if os.exists(filename) {
    net.send(
      r.from.sock,
      transmute([]u8)string(
        "HTTP/1.1 409 Conflict\r\n" +
        "Content-type: text/plain\r\n" +
        "\r\n" +
        "The file already exists\r\n",
      ),
    )
    return false
  }

  fd, err := os.open(filename, {.Write, .Create})
  defer os.close(fd)
  if err != nil {
    str := fmt.tprintfln(
      "HTTP/1.1 500 Internal Server Error\r\n" +
      "Content-type: text/plain\r\n" +
      "\r\n" +
      "Encountered an error while creating file: {}\r\n",
      err,
    )
    net.send(r.from.sock, transmute([]u8)(str))
    return false
  }

  send_fn ::
    linux_recv_file when false &&
    ODIN_OS == .Linux else multiplatform_recv_file

  if !send_fn(r, fd, filename) {
    os.remove(filename)
    fmt.printfln("could not finish writing files")
    return false
  }

  fmt.printfln("Finished receiving {} ({:M})", filename, r.content_length)

  str := fmt.tprintfln(
    "HTTP/1.1 201 Created\r\n" +
    "Content-type: text/plain\r\n" +
    "\r\n" +
    "File created successfully\r\n",
    err,
  )
  net.send(r.from.sock, transmute([]u8)(str))

  return false
}

@(private = "file")
multiplatform_recv_file :: proc(
  r: ^Request,
  fd: ^os.File,
  filename: string,
) -> bool {
  total_read := 0
  for total_read < r.content_length {
    buf, tcp_err := tcp_reader.empty_buffer(&r.from)
    if tcp_err != .None do return false
    fmt.printf(
      "Receiving {} ({:M}) {: 3d}%%\r",
      filename,
      r.content_length,
      (total_read * 100 / r.content_length),
    )
    total_read += len(buf)
    if written, err := os.write(fd, buf); err != nil {
      str := fmt.tprintfln(
        "HTTP/1.1 500 Internal Server Error\r\n" +
        "Content-type: text/plain\r\n" +
        "\r\n" +
        "Encountered an error while writing file: {}\r\n",
        err,
      )
      net.send(r.from.sock, transmute([]u8)(str))
      return false
    }
  }
  return true
}

@(private = "file")
linux_recv_file :: proc(r: ^Request, fd: ^os.File, filename: string) -> bool {
  total_read := 0

  // dump remaining buffered data
  buf, tcp_err := tcp_reader.empty_buffer(&r.from)
  if tcp_err != .None {
    os.remove(filename)
    return false
  }
  fmt.printf(
    "Receiving {} ({:M}) {: 3d}%%\r",
    filename,
    r.content_length,
    (total_read * 100 / r.content_length),
  )
  total_read += len(buf)
  if written, err := os.write(fd, buf); err != nil {
    send_error(
      r.from.sock,
      "Encountered an error while writing file: {}\r\n",
      err,
    )
    return false
  }

  // begin splicing
  pipes: [2]linux.Fd
  if pipes_err := linux.pipe2(&pipes, {}); pipes_err != .NONE {
    send_error(r.from.sock, "Could not create pipes")
    return false
  }

  fd_out := linux.Fd(os.fd(fd))
  fd_in := linux.Fd(r.from.sock)
  bytes_in_pipe: uint = 0
  // TODO: EINTR/EAGAIN should trigger a retry
  for total_read < r.content_length {
    written, err := linux.splice(
      fd_in,
      nil,
      pipes[0],
      nil,
      uint(r.content_length - total_read),
      {.MOVE, .MORE},
    )
    if err != .NONE {
      send_error(
        r.from.sock,
        "{} while splicing to pipe ({} total bytes)",
        err,
        total_read,
      )
      return false
    }
    bytes_in_pipe += uint(written)

    written, err = linux.splice(
      pipes[0],
      nil,
      fd_out,
      nil,
      bytes_in_pipe,
      {.MOVE, .MORE},
    )
    if err != .NONE {
      send_error(
        r.from.sock,
        "{} while splicing from pipe ({} total bytes)",
        err,
        total_read,
      )
      return false
    }
    total_read += written
    bytes_in_pipe -= uint(written)
  }
  if written, err := linux.splice(
    fd_in,
    nil,
    fd_out,
    nil,
    uint(r.content_length - total_read),
    {.MOVE},
  ); err != nil || written != r.content_length - total_read {
    send_error(
      r.from.sock,
      "Encountered an error while splicing file: {}\r\n",
      err,
    )
    return false
  }

  return true
}
