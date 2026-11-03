#+feature dynamic-literals
package html

import mo "../maybe_owned"
import "core:fmt"
import "core:io"
import "core:slice"
import "core:strings"
import "core:testing"

Str :: mo.Str

EMPTY_STR :: Str {
  elem = "",
  delete = proc(s: string) {},
}

Element :: struct {
  type:     string,
  props:    Str,
  children: Maybe([dynamic]Node),
}

Node :: union #no_nil {
  ^Element,
  Str,
}

el :: proc(
  type: string,
  children: ..Node,
  allocator := context.allocator,
  props: Str = EMPTY_STR,
) -> ^Element {
  return new_clone(
    Element {
      type = type,
      props = props,
      children = slice.to_dynamic(children, allocator),
    },
  )
}

dupstr :: proc(s: string) -> Str {
  return Str{elem = strings.clone(s), delete = proc(s: string) {delete(s)}}
}

str :: proc(s: string, delete := false) -> Str {
  return(
    Str{elem = s, delete = proc(s: string) {delete(s)}} if delete else mo.Unowned(s) \
  )
}

el_sc :: proc(type: string, props: Str = EMPTY_STR) -> ^Element {
  return new_clone(Element{type = type, props = props, children = nil})
}

// WARN: `delete(string)` only frees successfully if the allocator is context.allocator
to_props :: proc(
  m: map[string]string,
  allocator := context.allocator,
  consume := true,
) -> Str {
  sb := strings.builder_make(allocator)
  for k, v in m {
    strings.write_string(&sb, k)
    strings.write_rune(&sb, '=')
    strings.write_quoted_string(&sb, v)
  }
  return Str{strings.to_string(sb), proc(s: string) {
      delete(s)
    }}
}

delete_node :: proc(n: Node) {
  switch el in n {
  case ^Element:
    if children, ok := el.children.([dynamic]Node); ok {
      for c in children {
        delete_node(c)
      }
      if children != nil do delete(children)
    }
    mo.delete(el.props)
    free(el)
  case Str:
    mo.delete(el)
  }
}

debug :: proc(e: Node, spaces := 0) {
  _spaces :: proc(spaces: int) {
    for i in 0 ..< spaces do fmt.print("  ")
  }

  switch el in e {
  case ^Element:
    _spaces(spaces)
    fmt.printfln("<{} {}>", el.type, el.props.elem)
    if children, ok := el.children.([dynamic]Node); ok {
      for el in children {
        debug(el, spaces + 1)
      }
    } else {
      _spaces(spaces + 1)
      fmt.print("NO_ELEMS")
    }
    _spaces(spaces)
    fmt.printfln("</{}>", el.type)
  case Str:
    _spaces(spaces)
    fmt.printfln("\"{}\"", el.elem)
  }
}

to_html :: proc(e: Node, w: io.Writer, consume := true) -> io.Error {
  wr :: io.write_rune
  ws :: io.write_string

  switch e in e {
  case ^Element:
    if children, ok := e.children.([dynamic]Node); ok {
      wr(w, '<') or_return
      ws(w, e.type) or_return
      if e.props.elem != "" {
        wr(w, ' ') or_return
        ws(w, e.props.elem) or_return
      }
      wr(w, '>') or_return

      for c in children do to_html(c, w, consume = false)

      ws(w, "</") or_return
      ws(w, e.type) or_return
      wr(w, '>') or_return
    } else {
      wr(w, '<') or_return
      ws(w, e.type) or_return
      if e.props.elem != "" {
        wr(w, ' ') or_return
        ws(w, e.props.elem) or_return
      }
      ws(w, " />") or_return
    }
  case Str:
    ws(w, e.elem) or_return
  }
  if consume do delete_node(e)
  return .None
}

_bufwriter :: proc() -> io.Writer {
  return {
    data = new_clone(make([dynamic]byte)),
    procedure = proc(
      stream_data: rawptr,
      mode: io.Stream_Mode,
      p: []byte,
      offset: i64,
      whence: io.Seek_From,
    ) -> (
      n: i64,
      err: io.Error,
    ) {
      data := transmute(^[dynamic]byte)stream_data
      #partial switch mode {
      case .Write:
        append(data, ..p)
        return i64(len(p)), .None
      case .Read:
        return i64(copy(p, data[:])), .None
      case .Close:
        delete(data^)
        free(data)
        return 0, .None
      case:
        return 0, .Unsupported
      }
    },
  }
}

_html_matches :: proc(t: ^testing.T, root: Node, str: string) {
  w := _bufwriter()
  defer io.close(w)

  writer := _bufwriter()
  defer io.close(writer)
  to_html(root, writer)
  buf := make([]u8, len(str))
  defer delete(buf)
  n, _e := io.read(writer, buf)
  testing.expect_value(t, transmute(string)buf, str)
}

@(test)
_test0 :: proc(t: ^testing.T) {
  root := el("a")
  _html_matches(t, root, "<a></a>")
}

@(test)
_test1 :: proc(t: ^testing.T) {
  root := el("a", str("abc"))
  _html_matches(t, root, "<a>abc</a>")
}

@(test)
_test2 :: proc(t: ^testing.T) {
  root := el(
    "tr",
    el("td", str("dir")),
    str("abc"),
    el("td", el("a", str("def"), props = to_props({"href" = "index.html"}))),
  )
  _html_matches(
    t,
    root,
    "<tr><td>dir</td>abc<td><a href=\"index.html\">def</a></td></tr>",
  )
}
