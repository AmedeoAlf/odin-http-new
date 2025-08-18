package http

import "core:encoding/csv"
import "core:fmt"
import "core:net"
import "core:os"
import "core:path/filepath"
import "core:strings"

known_mime_types: map[string]string = nil

load_mime_types_from_csv :: proc(text: string) {
	r: csv.Reader
	r.trim_leading_space = true
	r.reuse_record = true
	r.reuse_record_buffer = true

	csv.reader_init_with_string(&r, text)
	defer csv.reader_destroy(&r)

	for record in csv.iterator_next(&r) {
		known_mime_types[strings.clone(record[0])] = strings.clone(record[1])
	}
}

get_filetype :: proc(filename: string) -> (mime: string) {
	ext := filepath.ext(filename)
	if ext == "" do return "application/octet_stream"
	return known_mime_types[ext[1:]] or_else "application/octet_stream"
}

send_file :: proc(sock: net.TCP_Socket, r: ^Request, file: os.Handle) {
	_send_file_header(sock, r)
	os.seek(file, i64(r.range_start), os.SEEK_SET)

	if r.range_end != 0 do _stream_file(sock, file, r.range_end - r.range_start)
	else do _stream_file(sock, file)
}

_send_file_header :: proc(sock: net.TCP_Socket, r: ^Request) {
	header := strings.builder_make()
	defer strings.builder_destroy(&header)

	file_size := os.file_size_from_path(r.route[1:])

	if (r.range_start == 0) {
		fmt.sbprintf(&header, "HTTP/1.1 200 OK\r\n")
		fmt.sbprintf(&header, "Content-length: %d\r\n", file_size)
	} else {
		end := r.range_end if r.range_end != 0 else int(file_size)
		fmt.sbprintf(&header, "HTTP/1.1 206 Partial\r\n")
		fmt.sbprintf(&header, "Content-range: bytes %d-%d/%d\r\n", r.range_start, end, file_size)
		fmt.sbprintf(&header, "Content-length: %d\r\n", end - r.range_start)
	}
	fmt.sbprintf(&header, "Content-type: %s\r\n", get_filetype(r.route[1:]))
	fmt.sbprintf(&header, "Accept-ranges: bytes\r\n")
	fmt.sbprintf(&header, "\r\n")

	net.send(sock, header.buf[:])

	// log(.DEBUG, "Sent headerer:")
	// log(.DEBUG, trim_for_print(string(header.buf[:])))
}

// TODO handle errors in some capacity
_stream_file :: proc(sock: net.TCP_Socket, file: os.Handle, size_limit := -1) {
	buf: [4096]byte

	read, read_err := os.read(file, buf[:])
	total_read := read

	for read_err == nil && read > 0 {
		send_err: net.Network_Error
		if size_limit == -1 || total_read < size_limit {
			_, send_err = net.send(sock, buf[:read])
		} else {
			_, send_err = net.send(sock, buf[:read + size_limit - total_read])
			break
		}
		// if send_err != net.TCP_Send_Error.Connection_Closed && send_err != nil {
		// log(.ERROR, send_err, "in send()")
		// }
		read, read_err = os.read(file, buf[:])
		total_read += read
	}

	// if read_err != nil {
	//   log(.ERROR, read_err, "in read()")
	// }
}
