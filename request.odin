package http

import "core:net"
import "core:reflect"
import "core:strconv"
import "core:strings"

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
  // TODO finish
}

Request :: struct {
  method:                 Http_Method,
  route:                  string,
  version:                Http_Version,
  range_start, range_end: int,
  content_length:         int,
  raw:                    []u8,
  body:                   []u8,
  from:                   net.TCP_Socket,
  from_addr:              net.Endpoint,
}

parse_method :: proc(str: string) -> (method: Http_Method, ok: bool) {
  for method, i in reflect.enum_field_names(Http_Method) {
    if str == method {
      // FIXME, could be more robust
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

// NOTE remember to delete(r.route)
fill_first_line_data :: proc(into: ^Request, line: string) -> (ok: bool) {
  parts := strings.split(line, " ")
  defer delete(parts)

  into.method = parse_method(parts[0]) or_return
  into.route = net.percent_decode(parts[1]) or_return
  into.version = parse_version(parts[2]) or_return

  return true
}

// Returns the last incomplete line
parse_headers :: proc(r: ^Request, from := 0) -> int {
  if from == -1 do return -1

  lines := strings.split_lines(string(r.raw)[from:])
  defer delete(lines)

  for line in lines {
    if line == "" do return -1
    RANGE_TEXT :: "Range: bytes="
    CONTENT_LENGTH_TEXT :: "Content-Length: "
    switch {
    case strings.starts_with(line, RANGE_TEXT):
      {
        start_end := line[len(RANGE_TEXT):] // ex. "100-1024"
        separator_position := strings.index_byte(start_end, '-')
        r.range_start = strconv.atoi(start_end[:separator_position])
        r.range_end = strconv.atoi(start_end[separator_position + 1:])
      }
    case strings.starts_with(line, CONTENT_LENGTH_TEXT):
      {
        r.content_length = strconv.atoi(line[len(CONTENT_LENGTH_TEXT):])
      }
    }
  }

  // fmt.println("[REQUEST]", match.groups[0])

  return strings.last_index(string(r.raw), "\r\n") + 2
}

delete_request :: proc(r: Request) {
  delete(r.route)
}
