package http

import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

slash_as_index_html: Request_Handler : proc(r: ^Request) -> bool {
	if r.route != "/" do return true

	file, err := os.open("index.html")
	if file == os.INVALID_HANDLE || err != nil do return true
	defer os.close(file)

	send_file(r.from, r, file)

	return false
}

resolve_file: Request_Handler : proc(r: ^Request) -> bool {
	file, err := os.open(r.route[1:])
	if file == os.INVALID_HANDLE || err != nil do return true
	defer os.close(file)

	send_file(r.from, r, file)

	return false
}

send_404: Request_Handler : proc(r: ^Request) -> bool {
	net.send(
		r.from,
		transmute([]u8)string(
			"HTTP/1.1 404 Not Found\r\n" +
			"Content-type: text/plain\r\n" +
			"\r\n" +
			"404 Not Found\r\n",
		),
	)
	return false
}

send_directory_listing: Request_Handler : proc(r: ^Request) -> bool {
	if r.route != "/" && !os.is_dir(r.route[1:]) do return true

	dir, err := os.open(r.route[1:] if len(r.route) > 1 else ".")
	defer os.close(dir)
	if err != nil do return true

	files, err2 := os.read_dir(dir, 50)
	defer os.file_info_slice_delete(files)
	if err2 != nil do return true

	send_lines :: proc(r: ^Request, lines: []string, newline := "\n") {
		for line in lines {
			net.send(r.from, transmute([]u8)line)
			net.send(r.from, transmute([]u8)string(newline))
		}
	}

	net.send(
		r.from,
		transmute([]u8)string("HTTP/1.1 200 OK\r\n" + "Content-type: text/html\r\n" + "\r\n"),
	)
	net.send(
		r.from,
		transmute([]u8)string(
			"<!DOCTYPE html>\n" +
			"<html lang=\"en\">\n" +
			"<head>\n" +
			"  <meta charset=\"UTF-8\">\n" +
			"  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" +
			"<title>Directory listing</title>\n" +
			"</head>\n" +
			"<body>\n" +
			"  <table>\n" +
			"    <thead>\n" +
			"      <tr>\n" +
			"        <th>Size</th>\n" +
			"        <th>Name</th>\n" +
			"      </tr>\n" +
			"    </thead>\n" +
			"    <tbody>\n",
		),
	)

	builder := strings.builder_make_none()
	for f in files {

		UNITS :: []struct {
			size: i64,
			sym:  rune,
		} {
			{mem.Terabyte, 'T'},
			{mem.Gigabyte, 'G'},
			{mem.Megabyte, 'M'},
			{mem.Kilobyte, 'K'},
			{mem.Byte, 'B'},
		}
		filesize := f32(f.size)
		suffix: rune

		for unit in UNITS {
			if f.size >= unit.size {
				filesize /= f32(unit.size)
				suffix = unit.sym
				break
			}
		}

		strings.builder_reset(&builder)
		fmt.sbprintfln(&builder, "      <tr>")
		fmt.sbprintfln(&builder, "        <td>%.1f%c</td>", filesize, suffix)
		fmt.sbprintfln(
			&builder,
			"        <td><a href=\"%s/%s\">%s</a></td>",
			r.route[1:],
			f.name,
			f.name,
		)
		fmt.sbprintfln(&builder, "      </tr>")
		net.send(r.from, builder.buf[:])
	}
	strings.builder_destroy(&builder)


	net.send(
		r.from,
		transmute([]u8)string("    </tbody>\n" + "  </table>\n" + "</body>\n" + "</html>"),
	)

	return false
}
