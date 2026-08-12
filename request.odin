package http

import "core:fmt"
import "core:net"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "tcp_reader"

Http_Version :: enum {
  HTTP1,
  HTTP1_1,
}

Http_Method :: enum {
  GET,
  POST,
  PUT,
  HEAD,
  PATCH,
  // TODO: finish
}

Request :: struct {
  method:                 Http_Method,
  raw_route:              string,
  route:                  string,
  params:                 string,
  version:                Http_Version,
  range_start, range_end: int,
  content_length:         int,
  from:                   tcp_reader.Reader,
  from_addr:              net.Endpoint,
}

parse_method :: proc(str: string) -> (method: Http_Method, ok: bool) {
  for method, i in reflect.enum_field_names(Http_Method) {
    if str == method {
      // FIXME: could be more robust
      return Http_Method(i), true
    }
  }
  return nil, false
}

parse_version :: proc(str: string) -> (version: Http_Version, ok: bool) {
  switch str {
  case "HTTP/1":
    return .HTTP1, true
  case "HTTP/1.1":
    return .HTTP1_1, true
  case:
    return nil, false
  }
}

// NOTE: remember to delete(r.raw_route)
fill_first_line_data :: proc(into: ^Request, line: string) -> (ok: bool) {
  parts := strings.split(line, " ")
  defer delete(parts)

  into.method = parse_method(parts[0]) or_return
  into.raw_route = net.percent_decode(parts[1]) or_return
  into.route, into.params = split_params(into.raw_route)
  into.version = parse_version(parts[2]) or_return

  return true
}


parse_header_line :: proc(r: ^Request, line: string) {
  RANGE_TEXT :: "Range: bytes="
  CONTENT_LENGTH_TEXT :: "Content-Length: "
  switch {
  case strings.starts_with(line, RANGE_TEXT):
    {
      start_end := line[len(RANGE_TEXT):] // ex. "100-1024"
      separator_position := strings.index_byte(start_end, '-')
      r.range_start =
        strconv.parse_int(start_end[:separator_position]) or_else 0
      r.range_end =
        strconv.parse_int(start_end[separator_position + 1:]) or_else 0
    }
  case strings.starts_with(line, CONTENT_LENGTH_TEXT):
    {
      r.content_length =
        strconv.parse_int(line[len(CONTENT_LENGTH_TEXT):]) or_else 0
    }
  }
}

delete_request :: proc(r: Request) {
  delete(r.raw_route)
}
