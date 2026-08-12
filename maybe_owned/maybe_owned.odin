package maybe_owned

Maybe_Owned :: struct($T: typeid) {
  elem:   T,
  delete: proc(t: T),
}

delete :: #force_inline proc(m: Maybe_Owned($T)) {
  m.delete(m.elem)
}

Unowned :: #force_inline proc(t: $T) -> Maybe_Owned(T) {
  return Maybe_Owned(T){elem = t, delete = proc(t: T) {}}
}
