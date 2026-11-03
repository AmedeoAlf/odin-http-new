package utils

import "core:io"
import "core:net"
import "core:slice"
import "core:testing"

get_first_n_sorted :: proc(
  elements: []$T,
  $n: int,
  compare: proc(a, b: T) -> slice.Ordering,
) -> (
  first_n: [n]T,
  filled: int,
) {
  copy(first_n[:], elements)

  if len(elements) < filled {
    filled = len(elements)
    return
  }

  filled = n

  slice.sort(first_n[:])
  for i in n ..< len(elements) {
    idx, _ := slice.binary_search_by(first_n[:], elements[i], compare)
    (idx != n) or_continue
    copy(first_n[idx + 1:], first_n[idx:])
    first_n[idx] = elements[i]
  }
  return
}

/*
 * src/llvm_backend_general.cpp(1597): Assertion Failure: `addr.addr.value != nullptr` 
 * This is a compiler error. Please report this.
 * 
 * One day this test will run, I'm confident
*/
@(test)
_first_n_test :: proc(t: ^testing.T) {
  arr := []int{10, 11, 12, 13, 14, 5, 10, 11, 7, 1, 2}
  first_n, filled := get_first_n_sorted(arr, 4, slice.cmp)
  testing.expect_value(t, first_n, [4]int{1, 2, 5, 7})
}

// will never close the socket
sock_to_writer :: proc(sock: net.TCP_Socket) -> io.Writer {
  return io.Writer {
    proc(
      stream_data: rawptr,
      mode: io.Stream_Mode,
      p: []byte,
      offset: i64,
      whence: io.Seek_From,
    ) -> (
      n: i64,
      err: io.Error,
    ) {
      sock := transmute(net.TCP_Socket)stream_data
      if mode != .Write do return 0, .Unsupported
      written, tcp_err := net.send_tcp(sock, p)
      #partial switch tcp_err {
      case .None:
        return i64(written), .None
      case .Connection_Closed,
           .Not_Connected,
           .Network_Unreachable,
           .Timeout,
           .Host_Unreachable:
        return 0, .Closed
      case .Insufficient_Resources:
        return 0, .Short_Buffer
      case .Invalid_Argument:
        return 0, .Invalid_Write
      case:
        return 0, .Unknown
      }
    },
    transmute(rawptr)sock,
  }
}
