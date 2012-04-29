%Copyright [2012] [Farruco Sanjurjo Arcay]

%   Licensed under the Apache License, Version 2.0 (the "License");
%   you may not use this file except in compliance with the License.
%   You may obtain a copy of the License at

%       http://www.apache.org/licenses/LICENSE-2.0

%   Unless required by applicable law or agreed to in writing, software
%   distributed under the License is distributed on an "AS IS" BASIS,
%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%   See the License for the specific language governing permissions and
%   limitations under the License.

%% @hidden

-module(wsock_http).
-include("wsock.hrl").

-export([build/3, get_start_line_value/2, get_header_value/2]).
-export([decode/2, encode/1]).

-define(CTRL, "\r\n").

-spec decode(Data::binary(), Type::request | response) -> {ok,#http_message{}} | {error, malformed_request}.
decode(Data, Type) ->
  [StartLine | Headers] = split(Data),
  StartLineProcessed = process_startline(StartLine, Type),
  HeadersProcessed = process_headers(Headers),

  case {StartLineProcessed, HeadersProcessed} of
    {{error, _}, _} ->
      {error, malformed_request};
    {_, {error, _}} ->
      {error, malformed_request};
    {{ok, StartLineList}, {ok, HeaderList}} ->
          {ok, wsock_http:build(Type, StartLineList, HeaderList)}
  end.


-spec build(Type::atom(), StartLine::list({atom(), string()}), Headers::list({string(), string()})) -> list(string()).
build(Type, StartLine, Headers) ->
  #http_message{type = Type, start_line = StartLine, headers = Headers}.

-spec encode(Message::#http_message{}) -> list(string()).
encode(Message) ->
  encode(Message, Message#http_message.type).

-spec encode(Message::#http_message{}, Type:: request | response) -> list(string()).
encode(Message, request) ->
  build_request_line(
    Message#http_message.start_line,
    build_headers(Message#http_message.headers, ["\r\n"])
  );

encode(Message, response) ->
  Version = wsock_http:get_start_line_value(version, Message),
  Status  = wsock_http:get_start_line_value(status, Message),
  Reason = wsock_http:get_start_line_value(reason, Message),
  Headers = Message#http_message.headers,

  ["HTTP/" ++ Version ++ " " ++ Status ++ " " ++ Reason ++ "\r\n" | build_headers(Headers, ["\r\n"])].
-spec build_headers(list({HeaderName::string(), HeaderValue::string()}), list(string())) -> list(string()).
build_headers(Headers, Acc) ->
  lists:foldr(fun({Key, Value}, AccIn) ->
        [ Key ++ ": " ++ Value ++ "\r\n" | AccIn]
    end, Acc, Headers).

-spec build_request_line(list({Name::atom(), Value::string()}), list(string())) -> list(string()).
build_request_line(RequestLine, Acc) ->
  Method   = proplists:get_value(method, RequestLine),
  Version  = proplists:get_value(version, RequestLine),
  Resource = proplists:get_value(resource, RequestLine),

  [Method ++ " " ++ Resource ++ " " ++ "HTTP/" ++ Version ++ "\r\n" | Acc].

-spec get_start_line_value(Key::atom(), Message::#http_message{}) -> string().
get_start_line_value(Key, Message) ->
  proplists:get_value(Key, Message#http_message.start_line).

-spec get_header_value(Key::string(), Message::#http_message{}) -> string().
get_header_value(Key, Message) ->
  LowerCasedKey = string:to_lower(Key),
  get_header_value_case_insensitive(LowerCasedKey, Message#http_message.headers).

-spec get_header_value_case_insensitive(Key::string(), list()) ->  undefined;
(Key::string(), list()) -> string().
get_header_value_case_insensitive(_, []) ->
  undefined;

get_header_value_case_insensitive(Key, [{Name, Value} | Tail]) ->
  LowerCaseName = string:to_lower(Name),
  case Key == LowerCaseName of
    true ->
      Value;
    false ->
      get_header_value_case_insensitive(Key, Tail)
  end.

%=============
% Helpers
%=============
-spec split(Data::binary()) -> list(binary()).
split(Data)->
  Fragments =   lists:map(fun(Element) ->
        re:replace(Element, <<"^\n*\s*|\n*\s*$">>, <<"">>, [global, {return, binary}])
    end, binary:split(Data, <<?CTRL>>, [trim, global])),

  lists:filter(fun(Element) ->
        <<>> =/= Element
    end, Fragments).

-spec process_startline(StartLine::binary(), Type:: request | response) -> list() | {error, term()}.
process_startline(StartLine, request) ->
  process_startline(StartLine, "(GET)\s+([\S/])\s+HTTP\/([0-9]\.[0-9])", [method, resource, version]);

process_startline(StartLine, response) ->
  process_startline(StartLine, "HTTP/([0-9]\.[0-9])\s([0-9]{3,3})\s([a-zA-z0-9 ]+)", [version, status, reason]).

-spec process_startline(StartLine::binary(), Regexp::list(), Keys::list(atom())) -> term().
process_startline(StartLine, Regexp, Keys) ->
  case regexp_run(Regexp, StartLine) of
    {match, [_ | Matchs]} ->
      {ok , lists:zip(Keys, Matchs)};
    nomatch -> {error, nomatch}
  end.

-spec regexp_run(Regexp::list(), String::binary()) -> {match, list()}.
regexp_run(Regexp, String) ->
  re:run(String, Regexp, [{capture, all, list}, caseless]).


-spec process_headers(Headers::list(binary())) -> list({list(), list()}).
process_headers(Headers) ->
  process_headers(Headers, []).

-spec process_headers(Headers::list(binary()), Acc::list({list(), list()})) -> list({list(), list()}) | {error, term()}.
process_headers([Header | Tail], Acc) ->
  case regexp_run("(.+)\s*:\s*(.+)", Header) of
    {match, [_Match, HeaderName, HeaderValue]} -> 
      process_headers(Tail, [{string:strip(HeaderName), HeaderValue} | Acc]);
    nomatch ->
      {error, nomatch}
  end;

process_headers([], Acc) ->
  {ok, Acc}.

