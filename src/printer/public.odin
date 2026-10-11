package printer 

import "core:fmt"
import "core:thread"
import "core:time"

println :: proc(args: ..any, sep: string = " ") {
  if !_check_printer() {
    fmt.println(..args, sep = sep)
    return
  }

  _append_to_printer(fmt.aprintln(..args, sep = sep))
}

printfln :: proc(fmt_: string, args: ..any) {
  if (!_check_printer()) {
    fmt.printfln(fmt_, ..args)
    return
  }

  _append_to_printer(fmt.aprintfln(fmt_, ..args))
}

_printer_test :: proc() {
  print_fast :: proc(idx: int) {
    for i in 0 ..< 100 {
      printfln("Thread {} says {:3d} at {}", idx, i, time.tick_now())
    }
  }
  threads: [4]^thread.Thread
  for &th, i in threads {
    th = thread.create_and_start_with_poly_data(i, print_fast)
  }
  thread.join_multiple(..threads[:])
  for t in threads do thread.destroy(t)
}
