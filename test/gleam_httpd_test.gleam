import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/httpd
import gleam/list
import gleam/option
import gleam/otp/actor
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn hello_world_test() {
  let subject = process.new_subject()

  // Start the server
  let assert Ok(actor.Started(pid:, ..)) =
    fn(request) {
      process.send(subject, request)
      response.new(202)
      |> response.set_body(bytes_tree.from_string("Hello, Mike!"))
      |> response.prepend_header("x-one", "hello")
      |> response.prepend_header("x-TWO", "hello")
      |> response.prepend_header("x-unicode", "🥳")
    }
    |> httpd.new
    |> httpd.port(6478)
    |> httpd.start()

  // Send a HTTP request
  let assert Ok(request) =
    request.to("http://127.0.0.1:6478/wibble/wobble?yes=no")
  let request =
    request
    |> request.set_method(http.Put)
    |> request.set_body("Hello, Joe!")
    |> request.prepend_header("x-in-one", "hello")
    |> request.prepend_header("x-in-TWO", "hello")

  // Verify the response
  let assert Ok(response.Response(status:, headers:, body:)) =
    httpc.send(request)
  assert status == 202
  assert body == "Hello, Mike!"
  assert headers
    |> list.key_set("date", "tuesday")
    == [
      #("connection", "close"),
      #("date", "tuesday"),
      #("content-length", "12"),
      #("content-type", "text/html"),
      #("x-unicode", "ð\u{009F}¥³"),
      #("x-two", "hello"),
      #("x-one", "hello"),
    ]

  // Shut down the server
  process.send_exit(pid)

  // Get the HTTP request and verify it
  let assert Ok(request.Request(
    method:,
    headers:,
    body:,
    scheme:,
    host:,
    port:,
    path:,
    query:,
  )) = process.receive(subject, 10)

  assert method == http.Put
  assert body == <<"Hello, Joe!">>
  assert scheme == http.Http
  assert host == "127.0.0.1"
  assert port == option.Some(6478)
  assert path == "/wibble/wobble"
  assert query == option.Some("yes=no")
  assert headers
    == [
      #("x-in-two", "hello"),
      #("x-in-one", "hello"),
      #("connection", "close"),
      #("host", "127.0.0.1:6478"),
      #("user-agent", "gleam_httpc/5.0.0"),
      #("content-length", "11"),
      #("content-type", "application/octet-stream"),
    ]
}

pub fn max_body_size_test() {
  let assert Ok(actor.Started(pid:, ..)) =
    fn(_) {
      response.new(200)
      |> response.set_body(bytes_tree.from_string("ok"))
    }
    |> httpd.new
    |> httpd.port(6479)
    |> httpd.max_body_size(5)
    |> httpd.start()

  let assert Ok(request) = request.to("http://127.0.0.1:6479/")
  let request =
    request
    |> request.set_method(http.Post)
    |> request.set_body("123456")

  let assert Ok(response) = httpc.send(request)
  assert response.status == 413
  assert response.body == "<HTML>
       <HEAD>
           <TITLE>Request Entity Too Large</TITLE>
      </HEAD>
      <BODY>
      <H1>Request Entity Too Large</H1>
Entity: Body too long
</BODY>
      </HTML>
"

  process.send_exit(pid)
}

pub fn max_header_size_test() {
  let assert Ok(actor.Started(pid:, ..)) =
    fn(_) {
      response.new(200)
      |> response.set_body(bytes_tree.from_string("ok"))
    }
    |> httpd.new
    |> httpd.port(6480)
    |> httpd.max_header_size(80)
    |> httpd.start()

  let assert Ok(request) = request.to("http://127.0.0.1:6480/")
  let request =
    request
    |> request.prepend_header(
      "x-too-large",
      "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz",
    )

  let assert Ok(response) = httpc.send(request)
  assert response.status == 413
  assert response.body == "<HTML>
       <HEAD>
           <TITLE>Request Entity Too Large</TITLE>
      </HEAD>
      <BODY>
      <H1>Request Entity Too Large</H1>
Entity: Headers unreasonably long
</BODY>
      </HTML>
"

  process.send_exit(pid)
}

pub fn max_uri_size_test() {
  let assert Ok(actor.Started(pid:, ..)) =
    fn(_) {
      response.new(200)
      |> response.set_body(bytes_tree.from_string("ok"))
    }
    |> httpd.new
    |> httpd.port(6481)
    |> httpd.max_uri_size(10)
    |> httpd.start()

  let assert Ok(request) = request.to("http://127.0.0.1:6481/1234567890")

  let assert Ok(response) = httpc.send(request)
  assert response.status == 414
  assert response.body == "<HTML>
       <HEAD>
           <TITLE>Request-URI Too Large</TITLE>
      </HEAD>
      <BODY>
      <H1>Request-URI Too Large</H1>
Message URI unreasonably long.
</BODY>
      </HTML>
"

  process.send_exit(pid)
}
