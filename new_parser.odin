package http

import "core:fmt"
import "core:net"
import "core:strings"
import mo "maybe_owned"

handle_client :: proc(
  s: Server,
  client: net.TCP_Socket,
  endpoint: net.Endpoint,
) {
  defer net.close(client)

  request := Request {
    from = Tcp_Reader{sock = client},
    from_addr = endpoint,
  }
  reader := &request.from


  line, err := _read_line(reader)
  if err != nil {
    fmt.eprintln("fail with", err)
    return
  }
  if !fill_first_line_data(&request, line.elem) {
    fmt.eprintfln("couldn't parse first line '{}'", line)
    return
  }
  mo.delete(line)

  line, err = _read_line(reader)
  for err == nil && line.elem != "" {
    parse_header_line(&request, line.elem)
    mo.delete(line)
    line, err = _read_line(reader)
  }
  mo.delete(line)

  for handler in s.handlers do handler(&request) or_break
}


Tcp_Reader :: struct {
  sock:        net.TCP_Socket,
  valid_until: int,
  next_b:      int,
  data:        [1000]byte,
}

_read_line :: proc(
  reader: ^Tcp_Reader,
  delim := "\r\n",
  allocator := context.allocator,
) -> (
  line: mo.Maybe_Owned(string),
  err: net.TCP_Recv_Error,
) {
  // 1. check available bytes in buffer
  data := reader.data[reader.next_b:reader.valid_until]
  found := strings.index(string(data), delim)
  if found != -1 {
    line = mo.Unowned(string(data[:found]))
    reader.next_b = reader.next_b + found + len(delim)
    return line, .None
  }

  // 2. let's use a heap dynamic array
  line_buf := make([dynamic]byte, allocator)
  // 2.1. copy the remaining bytes from the reader buffer
  append(&line_buf, ..data)

  found = -1
  search_from: int
  // 2.2. read bytes into 'line_buf'
  for found == -1 {
    old_len := len(line_buf)
    resize(&line_buf, len(line_buf) + len(reader.data))
    read, err := net.recv_tcp(reader.sock, line_buf[old_len:])
    if err != nil {
      delete(line_buf)
      return mo.Unowned(""), err
    }
    resize(&line_buf, old_len + read)

    search_from = max(old_len - len(delim) + 1, 0)
    found = strings.index(string(line_buf[search_from:]), delim)
  }
  // 2.3. copy remaining bytes, at the start of the reader buffer
  to_copy := line_buf[search_from + found + len(delim):]
  copy(reader.data[:], to_copy)
  reader.valid_until = len(to_copy)
  reader.next_b = 0
  resize(&line_buf, search_from + found)
  append(&line_buf, ..data)
  return {string(line_buf[:]), proc(s: string) {delete(s)}}, .None
}
