#+private
package printer

import "core:fmt"
import "core:sync"
import "core:sync/chan"
import "core:testing"
import "core:thread"
import "core:time"

Printer_Status :: enum {
  Uninit,
  Ok,
  CantCreate,
}

Printer :: struct {
  mutex:      sync.Mutex,
  print_chan: chan.Chan(string),
  status:     Printer_Status,
  last_print: time.Tick,
}

_printer: Printer

MIN_PRINT_TIME_RES :: 500 * time.Millisecond

_printer_thread :: proc() {
  for {
    time.sleep(MIN_PRINT_TIME_RES)

    now := time.tick_now()
    str := chan.recv(_printer.print_chan) or_continue
    fmt.print(str, flush = false)
    delete(str)
    for str in chan.try_recv(_printer.print_chan) {
      fmt.print(str, flush = false)
      delete(str)
    }
    fmt.print(flush = true)

    _printer.last_print = now
  }
}

_check_printer :: proc() -> bool {
  if _printer.status != .Ok {
    sync.mutex_lock(&_printer.mutex)
    if _printer.status == .Ok do return true
    channel, err := chan.create(chan.Chan(string), 10, context.allocator)
    if err != .None {
      if _printer.status != .CantCreate {
        fmt.eprintfln(
          "{} while creating printer channel, all prints will not be buffered",
          err,
        )
        _printer.status = .CantCreate
      }
      return false
    }
    _printer.print_chan = channel
    thread.create_and_start(_printer_thread)
    _printer.status = .Ok
    sync.mutex_unlock(&_printer.mutex)
  }
  return true
}

_append_to_printer :: proc(str: string) {
  chan.send(_printer.print_chan, str)
  fmt.println(_printer.print_chan.impl)
}
