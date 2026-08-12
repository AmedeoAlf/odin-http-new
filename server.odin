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

make_and_run_forever :: proc(
  interface: net.Endpoint,
  handlers := []Request_Handler{},
) -> net.Network_Error {
  run_forever(make_server(interface, handlers) or_return)
  return nil
}
