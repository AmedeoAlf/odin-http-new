package http

import "core:fmt"
import "core:net"
import "core:strings"
import mo "maybe_owned"
import tcp_reader "tcp_reader"

handle_client :: proc(
  s: Server,
  client: net.TCP_Socket,
  endpoint: net.Endpoint,
) {
  defer net.close(client)

  request := Request {
    from = tcp_reader.Reader{sock = client},
    from_addr = endpoint,
  }
  reader := &request.from


  line, err := tcp_reader.read_line(reader)
  if err != nil {
    fmt.eprintln("fail with", err)
    return
  }
  if !fill_first_line_data(&request, line.elem) {
    fmt.eprintfln("couldn't parse first line '{}'", line)
    return
  }
  mo.delete(line)

  line, err = tcp_reader.read_line(reader)
  for err == nil && line.elem != "" {
    parse_header_line(&request, line.elem)
    mo.delete(line)
    line, err = tcp_reader.read_line(reader)
  }
  mo.delete(line)

  for handler in s.handlers do handler(&request) or_break
}
