%% Same as bench_validateheaders_plain, but bumps an ETS counter
%% immediately before every #http_request_h{} reconstruction inside
%% validate_headers/3 itself (the driver's own initial RH construction
%% per call is unrelated to what ASR optimizes and isn't counted).
-module(bench_validateheaders_counted).
-export([run/1]).

-record(http_request_h,{
 	  'cache-control',
 	  connection = "keep-alive",
 	  date,
 	  pragma,
 	  trailer,
 	  'transfer-encoding',
 	  upgrade,
 	  via,
 	  warning,
 	  accept,
 	  'accept-charset',
 	  'accept-encoding',
 	  'accept-language',
 	  authorization,
 	  expect,
 	  from,
 	  host,
 	  'if-match',
 	  'if-modified-since',
 	  'if-none-match',
 	  'if-range',
 	  'if-unmodified-since',
 	  'max-forwards',
	  'proxy-authorization',
 	  range,
 	  referer,
 	  te,
 	  'user-agent',
	  allow,
 	  'content-encoding',
 	  'content-language',
 	  'content-length' = "0",
	  'content-location',
 	  'content-md5',
 	  'content-range',
 	  'content-type',
	  expires,
 	  'last-modified',
	  other=[]
	 }).

run(N) ->
    bench_util:reset_counter(httprequesth),
    drive(N, undefined).

drive(0, Acc) -> Acc;
drive(N, _Acc) ->
    RH = #http_request_h{host = undefined, te = undefined, connection = undefined},
    Result = validate_headers(RH, "example.com", "HTTP/1.1"),
    drive(N - 1, Result).

validate_headers(RequestHeaders = #http_request_h{host = undefined},
		 Host, "HTTP/1.1" = Version) ->
    bench_util:bump(httprequesth),
    validate_headers(RequestHeaders#http_request_h{host = Host}, Host, Version);
validate_headers(RequestHeaders = #http_request_h{te = TE, connection = Conn}, _, "HTTP/1.1") ->
    case TE of
        undefined ->
            RequestHeaders;
        _TEValue ->
            NewConn = case Conn of
                undefined -> "TE";
                ExistingConn ->
                    case lists:member("te", connection_tokens(ExistingConn)) of
                        true -> ExistingConn;
                        false -> ExistingConn ++ ", TE"
                    end
            end,
            bench_util:bump(httprequesth),
            RequestHeaders#http_request_h{connection = NewConn}
    end;
validate_headers(RequestHeaders, _, _) ->
    RequestHeaders.

connection_tokens(undefined) ->
    [];
connection_tokens(Connection) ->
    ConnList = string:tokens(string:to_lower(Connection), ","),
    [string:trim(Token) || Token <- ConnList].
