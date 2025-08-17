package http

import "core:fmt"
import "core:net"
import "core:strings"
import "core:thread"

MULTITHREADED :: #config(MT, true)
MAX_REQUEST_BYTES :: #config(
  MAX_REQUEST_SIZE,
  1 << 20,
  /* 1MB */
)

Request_Handler :: proc(request: ^Request) -> bool

Server :: struct {
  sock:     net.TCP_Socket,
  handlers: []Request_Handler,
}

make_server :: proc(
  interface: net.Endpoint,
  handlers := []Request_Handler{},
) -> (
  server: Server,
  err: net.Network_Error,
) {
  sock, listen_err := net.listen_tcp(interface)
  return {sock, handlers}, listen_err
}

run_forever :: proc(server: Server) {
  for {
    client, addr, err := net.accept_tcp(server.sock)

    if err != nil {
      fmt.println("Error in accept_tcp:", err)
      continue
    }

    when MULTITHREADED {
      t := thread.create_and_start_with_poly_data3(
        server,
        client,
        addr,
        handle_client,
        self_cleanup = true,
      )
    } else {
      handle_client(server, client, addr)
    }
  }
}

handle_client :: proc(
  s: Server,
  client: net.TCP_Socket,
  endpoint: net.Endpoint,
) {
  defer net.close(client)

  raw_request := make([dynamic]byte, 4096)
  defer delete(raw_request)

  request := Request {
    from      = client,
    from_addr = endpoint,
  }

  // Read the start into buffer, might continue reading
  bytes_read, err := net.recv(client, raw_request[:])
  if err != nil do return
  resize(&raw_request, bytes_read)

  first_line := string(raw_request[:])[:strings.index(
    string(raw_request[:]),
    "\r\n",
  )]
  fill_first_line_data(&request, first_line)

  first_incomplete_line := parse_headers(&request)

  /*
   * Continue reading until either:
   *  - we read more than MAX_REQUEST_BYTES
   *  - we read the Content-Length header + we read >= the bytes specified
   *  - the request is GET or HEAD and we encountered an empty line
   */
  for len(raw_request) < MAX_REQUEST_BYTES &&
      (request.content_length == 0 ||
          len(raw_request) < request.content_length) &&
      (request.method != .GET && request.method != .HEAD ||
          first_incomplete_line != -1) {
    resize(&raw_request, len(raw_request) + 4096)
    bytes_read, err = net.recv(client, raw_request[len(raw_request) - 4096:])
    resize(&raw_request, len(raw_request) - 4096 + bytes_read)

    first_incomplete_line = parse_headers(&request, first_incomplete_line)

    if err != nil {
      // Just client stopping the connection
      if err != net.TCP_Recv_Error.Connection_Closed do panic("I didn't want to think of actual logic here, so here's a panic")
      return
    }
  }

  request.raw = raw_request[:]


  // log(.DEBUG, "[Got request] (", bytes_read, "bytes)")
  // log(.DEBUG, trim_for_print(string(buf[:])))

  defer delete_request(request)

  for handler in s.handlers do handler(&request) or_break
}

make_and_run_forever :: proc(
  interface: net.Endpoint,
  handlers := []Request_Handler{},
) -> net.Network_Error {
  run_forever(make_server(interface, handlers) or_return)
  return nil
}
