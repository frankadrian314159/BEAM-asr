%% Same as bench_scansystemliteral_plain, but bumps an ETS counter
%% immediately before every #xmerl_scanner{} reconstruction.
-module(bench_scansystemliteral_counted).
-export([run/1]).

-record(xmerl_fun_states, {event, hook, rules, fetch, cont}).
-record(xmerl_scanner, {
          encoding=undefined, standalone=no, environment=prolog,
          declarations=[], doctype_name, doctype_DTD=internal,
          comments=true, document=false, default_attrs=false, rules,
          keep_rules=false, namespace_conformant=false, xmlbase,
          xmlbase_cache, fetch_path=[], filename=file_name_unknown,
          validation=off, schemaLocation=[], space=preserve,
          event_fun, hook_fun, acc_fun, fetch_fun, close_fun,
          continuation_fun, rules_read_fun, rules_write_fun,
          rules_delete_fun, user_state, fun_states=#xmerl_fun_states{},
          entity_references=[], text_decl=false, quiet=false,
          col=1, line=1, common_data=[], allow_entities=false}).

-define(dbg(Fmt, Args), ok).
-define(fatal(Reason, S), fatal(Reason, S)).

fatal_fun(Reason) -> fun(S) -> ?fatal(Reason, S) end.
fatal(Reason, S) -> exit({fatal, {Reason, {line, S#xmerl_scanner.line}}}).

run(N) ->
    bench_util:reset_counter(xmerlscanner),
    Input = [$"] ++ lists:duplicate(N, $x) ++ [$"],
    S0 = #xmerl_scanner{continuation_fun = unused},
    scan_system_literal(Input, S0).

scan_system_literal([], S=#xmerl_scanner{continuation_fun = F}) ->
    ?dbg("cont()...~n", []),
    F(fun(MoreBytes, S1) -> scan_system_literal(MoreBytes, S1) end,
      fatal_fun(unexpected_end),
      S);
scan_system_literal("\"" ++ T, S) ->
    scan_system_literal(T, S, $", []);
scan_system_literal("'" ++ T, S) ->
    scan_system_literal(T, S, $', []).

scan_system_literal([], S=#xmerl_scanner{continuation_fun = F},
		    Delimiter, Acc) ->
    ?dbg("cont()...~n", []),
    F(fun(MoreBytes, S1) -> scan_system_literal(MoreBytes,S1,Delimiter,Acc) end,
      fatal_fun(unexpected_end),
      S);
scan_system_literal([H|T], S, H, Acc) ->
    bench_util:bump(xmerlscanner),
    {lists:reverse(Acc), T, S#xmerl_scanner{col = S#xmerl_scanner.col+1}};
scan_system_literal("#"++_R, S, _H, _Acc) ->
    %% actually not a fatal error
    ?fatal(fragment_identifier_in_system_literal,S);
scan_system_literal(Str, S, Delimiter, Acc) ->
    {Ch,T} = to_ucs(S#xmerl_scanner.encoding,Str),
    bench_util:bump(xmerlscanner),
    scan_system_literal(T, S#xmerl_scanner{col = S#xmerl_scanner.col+1},
			Delimiter, [Ch|Acc]).

to_ucs(Encoding, Chars) when Encoding=="utf-8"; Encoding == undefined ->
    utf8_2_ucs(Chars);
to_ucs(_,[C|Rest]) ->
    {C,Rest}.

utf8_2_ucs([A,B,C,D|Rest]) when A band 16#f8 =:= 16#f0,
			      B band 16#c0 =:= 16#80,
			      C band 16#c0 =:= 16#80,
			      D band 16#c0 =:= 16#80 ->
    case ((D band 16#3f) bor ((C band 16#3f) bsl 6) bor
	  ((B band 16#3f) bsl 12) bor ((A band 16#07) bsl 18)) of
	Ch when Ch >= 16#10000 ->
	    {Ch,Rest};
	Ch ->
	    {{error,{bad_character,Ch}},Rest}
    end;
utf8_2_ucs([A,B,C|Rest]) when A band 16#f0 =:= 16#e0,
			    B band 16#c0 =:= 16#80,
			    C band 16#c0 =:= 16#80 ->
    case ((C band 16#3f) bor ((B band 16#3f) bsl 6) bor
	  ((A band 16#0f) bsl 12)) of
	Ch when Ch >= 16#800 ->
	    {Ch,Rest};
	Ch ->
	    {{error,{bad_character,Ch}},Rest}
    end;
utf8_2_ucs([A,B|Rest]) when A band 16#e0 =:= 16#c0,
			  B band 16#c0 =:= 16#80 ->
    case ((B band 16#3f) bor ((A band 16#1f) bsl 6)) of
	Ch when Ch >= 16#80 ->
	    {Ch,Rest};
	Ch ->
	    {{error,{bad_character,Ch}},Rest}
    end;
utf8_2_ucs([A|Rest]) when A < 16#80 ->
    {A,Rest};
utf8_2_ucs([A|Rest]) ->
    {{error,{bad_character,A}},Rest}.
