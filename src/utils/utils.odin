package utils

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
