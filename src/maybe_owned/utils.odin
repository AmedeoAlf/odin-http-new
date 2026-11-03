package maybe_owned

import "core:fmt"

Str :: Maybe_Owned(string)

aprintf :: #force_inline proc(fmt_: string, args: ..any) -> Str {
  return Str{fmt.aprintf(fmt_, ..args), proc(s: string) {delete_string(s)}}
}

tprintf :: #force_inline proc(fmt_: string, args: ..any) -> Str {
  return Str{fmt.tprintf(fmt_, ..args), proc(s: string) {}}
}
