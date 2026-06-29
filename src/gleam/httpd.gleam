import gleam/bytes_tree.{type BytesTree}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/charlist.{type Charlist}
import gleam/erlang/process.{type Pid}
import gleam/http
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor.{type StartResult}
import gleam/string

pub type Configuration {
  Configuration(
    port: Int,
    bind: String,
    handler: fn(Request(BitArray)) -> Response(BytesTree),
  )
}

pub fn new(
  handler: fn(Request(BitArray)) -> Response(BytesTree),
) -> Configuration {
  Configuration(handler:, port: 3000, bind: "localhost")
}

pub fn port(config: Configuration, port: Int) -> Configuration {
  Configuration(..config, port:)
}

pub fn start(config: Configuration) -> StartResult(Nil) {
  let result =
    start_httpd(charlist.from_string(config.bind), config.port, fn(request) {
      let HttpdRequest(method:, uri:, headers:, body:, socket_type:) = request
      let method = case charlist.to_string(method) {
        "GET" -> http.Get
        "POST" -> http.Post
        "PUT" -> http.Put
        "DELETE" -> http.Delete
        "PATCH" -> http.Patch
        "HEAD" -> http.Head
        "OPTIONS" -> http.Options
        "TRACE" -> http.Trace
        "CONNECT" -> http.Connect
        other -> http.Other(other)
      }
      let headers =
        list.map(headers, fn(header) {
          #(charlist.to_string(header.0), charlist.to_string(header.1))
        })
      let scheme = case socket_type {
        IpComm -> http.Http
        Ssl -> http.Https
      }
      let #(host, port) = case list.key_find(headers, "host") {
        Ok(host) ->
          case string.split_once(host, ":") {
            Ok(#(host, port)) -> {
              let port = int.parse(port) |> option.from_result
              #(host, port)
            }
            Error(_) -> #(host, option.None)
          }
        Error(_) -> #("", option.None)
      }
      let path = charlist.to_string(uri)
      let #(path, query) = case string.split_once(path, "?") {
        Ok(#(path, query)) -> #(path, option.Some(query))
        Error(_) -> #(path, option.None)
      }
      let request =
        Request(method:, headers:, body:, scheme:, host:, port:, path:, query:)
      config.handler(request)
    })

  case result {
    Ok(pid) -> Ok(actor.Started(pid:, data: Nil))
    Error(error) -> Error(actor.InitExited(process.Abnormal(error)))
  }
}

type SocketType {
  IpComm
  Ssl
}

type HttpdRequest {
  HttpdRequest(
    method: Charlist,
    uri: Charlist,
    headers: List(#(Charlist, Charlist)),
    body: BitArray,
    socket_type: SocketType,
  )
}

@external(erlang, "gleam_httpd_ffi", "start")
fn start_httpd(
  bind: Charlist,
  port: Int,
  handler: fn(HttpdRequest) -> Response(BytesTree),
) -> Result(Pid, Dynamic)
