module main

// RequestQueue (server.v): the requests come out in the order they were read, and the current one
// is given up when a later one lints the same files.
fn test_request_queue_gives_up_superseded_requests() {
	requests := chan ServerRequest{cap: 8}
	mut queue := &RequestQueue{
		requests: requests
	}
	for files in ['a.ts', 'b.ts', '', 'a.ts'] {
		requests <- ServerRequest{
			files: files
		}
	}
	requests.close()
	mut order := []string{}
	mut stops := []bool{}
	for {
		request := queue.next() or { break }
		queue.current = request.files
		order << request.files
		stops << queue.stop()
	}
	assert order == ['a.ts', 'b.ts', '', 'a.ts']
	// a.ts is linted again later; b.ts, a request without files and the last a.ts are not.
	assert stops == [true, false, false, false]
}
