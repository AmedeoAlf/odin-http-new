#+private
package printer

import "core:fmt"
import "core:sync"
import "core:sync/chan"
import "core:terminal/ansi"
import "core:thread"
import "core:time"

Printer_Status :: enum {
  Uninit,
  Ok,
  CantCreate,
}

_Progress_Bar :: struct {
  name:     string,
  progress: f32,
}

Printer :: struct {
  mutex:            sync.Mutex,
  print_chan:       chan.Chan(string),
  status:           Printer_Status,
  progress_bars:    [dynamic]^_Progress_Bar,
  showing_progress: bool,
}

_printer: Printer

MIN_PRINT_TIME_RES :: 50 * time.Millisecond

_printer_thread :: proc() {
  for {
    time.sleep(MIN_PRINT_TIME_RES)

    now := time.tick_now()
    str := chan.recv(_printer.print_chan) or_continue

    // print should be implemented with fmt.print(..., flush=false)
    // BUT it's currently (2026-11-10) broken
    // https://github.com/odin-lang/Odin/issues/6656
    //
    // print :: proc(s: string) {
    //   fmt.print(str)
    // }
    Buf :: [dynamic; 4096]byte
    buf: Buf
    print :: proc(s: string, buf: ^Buf, progress_update: bool = false) {
      if s == "" do return

      if !progress_update && _printer.showing_progress {
        _printer.showing_progress = false
        print("\n", buf)
      }

      if cap(buf^) - len(buf^) < len(s) do flush(buf)

      if cap(buf) / 2 < len(s) {
        fmt.print(s)
      } else {
        append(buf, ..transmute([]byte)s)
      }
    }
    flush :: proc(buf: ^Buf) {
      fmt.print(string(buf[:]))
      clear(buf)
    }

    print(str, &buf)
    delete(str)
    for str in chan.try_recv(_printer.print_chan) {
      print(str, &buf)
      delete(str)
    }

    if len(_printer.progress_bars) > 0 {
      print_bar :: proc(bar: ^_Progress_Bar, buf: ^Buf) {
        val := sync.atomic_load(&bar.progress)
        if len(bar.name) < 30 {
          print(bar.name, buf, true)
        } else {
          strbuf: [30]byte
          str := fmt.bprintf(
            strbuf[:],
            "{}...{}",
            bar.name[:12],
            bar.name[len(bar.name) - 15:],
          )
          print(str, buf, true)
        }

        floatbuf: [20]byte
        float := fmt.bprintf(
          floatbuf[:],
          ansi.CSI +
          ansi.FG_GREEN +
          ansi.SGR +
          " {: 3.1f}%%" +
          ansi.CSI +
          ansi.RESET +
          ansi.SGR,
          val * 100,
        )
        print(float, buf, true)
      }

      MAX_DISPLAY :: 4
      for &bar, idx in _printer.progress_bars[:min(MAX_DISPLAY, len(_printer.progress_bars))] {
        if idx != 0 do print(", ", &buf, true)
        print_bar(bar, &buf)
      }
      if len(_printer.progress_bars) > MAX_DISPLAY {
        _buf: [10]byte
        str := fmt.bprintf(
          _buf[:],
          " (+{})",
          len(_printer.progress_bars[:]) - MAX_DISPLAY,
        )
        print(str, &buf, true)
      }
      print("\r", &buf, true)
      _printer.showing_progress = true
    }

    flush(&buf)
  }
}

_check_printer :: proc() -> bool {
  if _printer.status != .Ok {
    sync.mutex_lock(&_printer.mutex)
    if _printer.status == .Ok do return true

    if _printer.status == .Uninit {
      _printer.progress_bars = make([dynamic]^_Progress_Bar)
    }

    channel, err := chan.create(chan.Chan(string), 100, context.allocator)
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
}
