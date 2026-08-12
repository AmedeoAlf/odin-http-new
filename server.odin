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

  first_newline := strings.index(string(raw_request[:]), "\r\n")
  if first_newline == -1 do return
  fill_first_line_data(&request, string(raw_request[:])[:first_newline])

  request.raw = raw_request[:]
  first_incomplete_line := parse_headers(&request, first_newline + 2)

  body_start :=
    first_incomplete_line + 2 if string(raw_request[first_incomplete_line:][:2]) == "\r\n" else -1
  fmt.println(
    "body_start",
    body_start,
    string(raw_request[first_incomplete_line:]),
  )
  /*
   * Continue reading until either:
   *  - we read more than MAX_REQUEST_BYTES
   *  - we read the Content-Length header + we read >= the bytes specified
   *  - the request is GET or HEAD and we encountered an empty line
   */
  for len(raw_request) < MAX_REQUEST_BYTES &&
      (request.content_length == 0 ||
          len(raw_request) < request.content_length) &&
      (request.method == .GET || request.method == .HEAD && body_start == -1) {

    resize(&raw_request, len(raw_request) + 4096)
    bytes_read, err = net.recv(client, raw_request[len(raw_request) - 4096:])
    if err != nil {
      // Just client stopping the connection
      if err != net.TCP_Recv_Error.Connection_Closed do panic("I didn't want to think of actual logic here, so here's a panic")
      return
    }
    resize(&raw_request, len(raw_request) - 4096 + bytes_read)

    request.raw = raw_request[:]
    if body_start == -1 {
      first_incomplete_line = parse_headers(&request, first_incomplete_line)
      fmt.println(raw_request[first_incomplete_line:][:2])
      if string(raw_request[first_incomplete_line:][:2]) == "\r\n" {
        body_start = first_incomplete_line + 2
      }
    }
  }


  // log(.DEBUG, "[Got request] (", bytes_read, "bytes)")
  // log(.DEBUG, trim_for_print(string(buf[:])))

  defer delete_request(request)

  fmt.println(request.method, request.raw_route)
  if body_start != -1 do request.body = request.raw[body_start:]
  for handler in s.handlers do handler(&request) or_break
}

make_and_run_forever :: proc(
  interface: net.Endpoint,
  handlers := []Request_Handler{},
) -> net.Network_Error {
  run_forever(make_server(interface, handlers) or_return)
  return nil
}
