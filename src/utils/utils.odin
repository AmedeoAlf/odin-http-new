package utils

import "core:slice"

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
    _, idx := slice.binary_search_by(first_n, elements[i], compare)
    (idx != n) or_continue
    copy(first_n[idx + 1:], first_n[idx:])
    first_n[idx] = elements[i]
  }
  return
}
