# httpd

Bindings to Erlang's built in HTTP server, `httpd`.

[![Package Version](https://img.shields.io/hexpm/v/gleam_httpd)](https://hex.pm/packages/gleam_httpd)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://gleam-httpd.hexdocs.pm/)

```sh
gleam add gleam_httpd@1
```
```gleam
import gleam/httpd
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/bytes_tree.{type BytesTree}

// Write your request handler, a function that takes a request and 
// returns a response.
pub fn handle_request(_request: Request(BitArray)) -> Response(BytesTree) {
  let body = bytes_tree.from_string("Welcome!")
  response.new(200)
  |> response.set_body(body)
}

// Start a httpd server using your request handler.
pub fn start() -> _ {
  httpd.new(handle_request)
  |> httpd.port(3000)
  |> httpd.start
}
```

Further documentation can be found at <https://gleam-httpd.hexdocs.pm/>.

## When should you use this?

`httpd` is a HTTP1.1 server that is included with the standard Erlang
distribution. If you don't need web sockets, server sent events, request body
streaming, or higher HTTP versions then `httpd` could be a great choice! 

If you need more than `httpd` offers then there are more sophisticated BEAM
HTTP servers that you can add as a dependency and use, such as Ewe and Mist.
