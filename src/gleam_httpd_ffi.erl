-module(gleam_httpd_ffi).
-export([do/1, start/3]).
-include_lib("inets/include/httpd.hrl").

-define(handler, gleam_httpd_handler).

do(#mod{
    config_db = ConfigDb,
    method = Method,
    request_uri = RequestUri,
    parsed_header = Headers,
    entity_body = Body,
    socket_type = Socket
}) ->
    BinaryBody = iolist_to_binary(Body),
    Request = {httpd_request, Method, RequestUri, Headers, BinaryBody, Socket},
    Handler = httpd_util:lookup(ConfigDb, ?handler),
    {response, Status, ResponseHeaders, ResponseBody} = Handler(Request),
    CharlistHeaders = lists:map(fun({K, V}) -> 
        {binary_to_list(K), binary_to_list(V)}
    end, ResponseHeaders),
    FullHeaders = [
        {code, Status},
        {"content-length", integer_to_list(iolist_size(ResponseBody))}
        | CharlistHeaders
    ],
    Response = {response, FullHeaders, ResponseBody},
    {break, [{response, Response}]}.

start(BindAddress, Port, Handler) ->
    Config = [
        {server_root, "./"},
        {document_root, "./"},
        {port, Port},
        {bind_address, BindAddress},
        {modules, [?MODULE]},
        {?handler, Handler}
    ],
    inets:start(httpd, Config, stand_alone).
