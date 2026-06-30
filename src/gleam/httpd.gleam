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
import gleam/result
import gleam/string

pub opaque type Configuration {
  Configuration(
    port: Int,
    bind: String,
    keep_alive: Bool,
    keep_alive_timeout: Int,
    max_clients: Int,
    chunked_transfer_encoding: Bool,
    max_body_size: Int,
    max_header_size: Int,
    max_uri_size: Int,
    minimum_bytes_per_second: option.Option(Int),
    handler: fn(Request(BitArray)) -> Response(BytesTree),
  )
}

/// Create a new httpd configuration. See the functions in this module for the
/// configuration options and their default values.
///
pub fn new(
  handler: fn(Request(BitArray)) -> Response(BytesTree),
) -> Configuration {
  Configuration(
    handler:,
    port: 3000,
    bind: "localhost",
    keep_alive: True,
    keep_alive_timeout: 150,
    max_clients: 150,
    chunked_transfer_encoding: True,
    max_body_size: 2_000_000,
    max_header_size: 10_000,
    max_uri_size: 8000,
    minimum_bytes_per_second: option.None,
  )
}

/// The port to listen on. The default is 3000.
///
pub fn port(config: Configuration, port: Int) -> Configuration {
  Configuration(..config, port:)
}

/// Instructs the server whether to use persistent connections when the client
/// claims to be HTTP/1.1 compliant.
///
/// The default is true. 
///
pub fn keep_alive(config: Configuration, keep_alive: Bool) -> Configuration {
  Configuration(..config, keep_alive:)
}

/// The number of seconds the server waits for a subsequent request from a
/// HTTP/1.1 client before closing the connection.
///
/// Must be greater than zero. The default is 150.
///
/// If `keep_alive` is set to false then this option does nothing.
///
pub fn keep_alive_timeout(
  config: Configuration,
  seconds: Int,
) -> Configuration {
  let seconds = int.max(seconds, 1)
  Configuration(..config, keep_alive_timeout: seconds)
}

/// Limits the number of simultaneous requests that can be supported.
///
/// The default is 150.
///
pub fn max_clients(config: Configuration, max_clients: Int) -> Configuration {
  Configuration(..config, max_clients:)
}

/// Instructs the server whether to use chunked transfer-encoding when sending
/// a response to an HTTP/1.1 client.
///
/// The default is true.
///
pub fn chunked_transfer_encoding(
  config: Configuration,
  chunked_transfer_encoding: Bool,
) -> Configuration {
  Configuration(..config, chunked_transfer_encoding:)
}

/// Limits the size of the message body of an HTTP request.
///
/// The default is 2 MB.
///
pub fn max_body_size(config: Configuration, bytes limit: Int) -> Configuration {
  Configuration(..config, max_body_size: limit)
}

/// Limits the size of the message header of an HTTP request.
///
/// The default is 10 KB.
///
pub fn max_header_size(
  config: Configuration,
  bytes limit: Int,
) -> Configuration {
  Configuration(..config, max_header_size: limit)
}

/// Limits the size of the HTTP request URI.
///
/// The default is 8 KB.
///
pub fn max_uri_size(config: Configuration, bytes limit: Int) -> Configuration {
  Configuration(..config, max_uri_size: limit)
}

/// Sets a minimum of bytes per second value for connections.
///
/// If the value is unreached, the socket closes for that connection.
///
pub fn minimum_bytes_per_second(
  config: Configuration,
  limit: Int,
) -> Configuration {
  Configuration(..config, minimum_bytes_per_second: option.Some(limit))
}

/// Start the httpd server.
///
/// You should add this to your supervision tree.
///
pub fn start(config: Configuration) -> StartResult(Nil) {
  let optionally_add = fn(config, constructor, value) {
    case value {
      option.None -> config
      option.Some(value) -> [constructor(value), ..config]
    }
  }

  let config =
    [
      ServerRoot("./"),
      DocumentRoot("./"),
      ServerTokens(None),
      KeepAlive(config.keep_alive),
      KeepAliveTimeout(config.keep_alive_timeout),
      MaxClients(config.max_clients),
      DisableChunkedTransferEncodingSend(!config.chunked_transfer_encoding),
      MaxBodySize(config.max_body_size),
      MaxHeaderSize(config.max_header_size),
      MaxUriSize(config.max_uri_size),
      Port(config.port),
      BindAddress(charlist.from_string(config.bind)),
      Modules([GleamHttpdFfi]),
      GleamHttpdHandler(fn(request) { config.handler(convert_request(request)) }),
    ]
    |> optionally_add(MinimumBytesPerSecond, config.minimum_bytes_per_second)
  case start_httpd(Httpd, config, StandAlone) {
    Ok(pid) -> Ok(actor.Started(pid:, data: Nil))
    Error(error) -> Error(actor.InitExited(process.Abnormal(error)))
  }
}

fn convert_request(request: HttpdRequest) -> Request(BitArray) {
  let HttpdRequest(method:, uri:, headers:, body:, socket_type:) = request
  let method =
    charlist.to_string(method) |> http.parse_method |> result.unwrap(http.Get)
  let headers =
    list.map(headers, fn(header) {
      #(charlist.to_string(header.0), charlist.to_string(header.1))
    })
  let scheme = case socket_type {
    IpComm -> http.Http
    Ssl -> http.Https
  }
  let #(host, port) = parse_host(headers)
  let path = charlist.to_string(uri)
  let #(path, query) = case string.split_once(path, "?") {
    Ok(#(path, query)) -> #(path, option.Some(query))
    Error(_) -> #(path, option.None)
  }
  Request(method:, headers:, body:, scheme:, host:, port:, path:, query:)
}

fn parse_host(
  headers: List(#(String, String)),
) -> #(String, option.Option(Int)) {
  case list.key_find(headers, "host") {
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

@external(erlang, "inets", "start")
fn start_httpd(
  inets_service: InetsService,
  config: List(HttpdConfiguration),
  mode: StartMode,
) -> Result(Pid, Dynamic)

type InetsService {
  Httpd
}

type HttpdConfiguration {
  ServerRoot(String)
  DocumentRoot(String)
  ServerTokens(ServerTokens)
  Port(Int)
  BindAddress(Charlist)
  Modules(List(HttpdModule))
  GleamHttpdHandler(fn(HttpdRequest) -> Response(BytesTree))
  KeepAlive(Bool)
  KeepAliveTimeout(Int)
  MaxClients(Int)
  DisableChunkedTransferEncodingSend(Bool)
  MaxBodySize(Int)
  MaxHeaderSize(Int)
  MaxUriSize(Int)
  MinimumBytesPerSecond(Int)
}

type StartMode {
  StandAlone
}

type ServerTokens {
  None
}

type HttpdModule {
  GleamHttpdFfi
}
