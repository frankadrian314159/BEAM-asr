%% ASR Benchmark: httpc:validate_headers/3, extracted verbatim from
%% Erlang/OTP 28.5's lib/inets/src/http_client/httpc.erl (lines
%% 1974-1993) - one of the real corpus-study "unlocked loops" (v1.6:
%% update-expression transparency in its second clause's case-wrapped
%% body, plus Category D full-slice guard-conversion for its first
%% clause's `host=undefined` ground literal alias sub-pattern).
%%
%% #http_request_h{} copied verbatim from
%% lib/inets/src/http_lib/http_internal.hrl (lines 74-117) - the full
%% 39-field request-header record. http_util:connection_tokens/1
%% copied verbatim from lib/inets/src/http_lib/http_util.erl
%% (lines 249-253).
%%
%% Unlike the other newly-unlocked loops (which scan forward through a
%% string), validate_headers/3 is a short, bounded normalization (at
%% most 2 recursive hops regardless of input) - so N here means "call it
%% N times," a throughput benchmark, not "scan N characters."
-module(bench_validateheaders_plain).
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

run(N) -> drive(N, undefined).

drive(0, Acc) -> Acc;
drive(N, _Acc) ->
    RH = #http_request_h{host = undefined, te = undefined, connection = undefined},
    Result = validate_headers(RH, "example.com", "HTTP/1.1"),
    drive(N - 1, Result).

%% --- verbatim from httpc.erl:1974-1993 ---
validate_headers(RequestHeaders = #http_request_h{host = undefined},
		 Host, "HTTP/1.1" = Version) ->
    validate_headers(RequestHeaders#http_request_h{host = Host}, Host, Version);
validate_headers(RequestHeaders = #http_request_h{te = TE, connection = Conn}, _, "HTTP/1.1") ->
    case TE of
        undefined ->
            RequestHeaders;
        _TEValue ->
            NewConn = case Conn of
                undefined -> "TE";
                ExistingConn ->
                    %% Original calls http_util:connection_tokens/1;
                    %% inlined as a local call here since only that one
                    %% function is copied in, not the whole module.
                    case lists:member("te", connection_tokens(ExistingConn)) of
                        true -> ExistingConn;
                        false -> ExistingConn ++ ", TE"
                    end
            end,
            RequestHeaders#http_request_h{connection = NewConn}
    end;
validate_headers(RequestHeaders, _, _) ->
    RequestHeaders.

%% --- verbatim from http_util.erl:249-253 ---
connection_tokens(undefined) ->
    [];
connection_tokens(Connection) ->
    ConnList = string:tokens(string:to_lower(Connection), ","),
    [string:trim(Token) || Token <- ConnList].
