%% Same as bench_xmlvsn_plain, but bumps an ETS counter immediately
%% before every #xmerl_scanner{} reconstruction (records have no
%% runtime constructor to monkey-patch).
-module(bench_xmlvsn_counted).
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
    Input = [$"] ++ lists:duplicate(N, $1) ++ [$"],
    S0 = #xmerl_scanner{continuation_fun = unused},
    scan_xml_vsn(Input, S0).

scan_xml_vsn([], S=#xmerl_scanner{continuation_fun = F}) ->
    ?dbg("cont()...~n", []),
    F(fun(MoreBytes, S1) -> scan_xml_vsn(MoreBytes, S1) end,
      fatal_fun(unexpected_end),
      S);
scan_xml_vsn([H|T], S) when H==$"; H==$'->
    bench_util:bump(xmerlscanner),
    xml_vsn(T, S#xmerl_scanner{col = S#xmerl_scanner.col+1}, H, []).

xml_vsn([H|T], S=#xmerl_scanner{col = C}, H, Acc) ->
    bench_util:bump(xmerlscanner),
    {lists:reverse(Acc), T, S#xmerl_scanner{col = C+1}};
xml_vsn([H|T], S=#xmerl_scanner{col = C},Delim, Acc) when H >= $a, H =< $z ->
    bench_util:bump(xmerlscanner),
    xml_vsn(T, S#xmerl_scanner{col = C+1}, Delim, [H|Acc]);
xml_vsn([H|T], S=#xmerl_scanner{col = C},Delim, Acc) when H >= $A, H =< $Z ->
    bench_util:bump(xmerlscanner),
    xml_vsn(T, S#xmerl_scanner{col = C+1}, Delim, [H|Acc]);
xml_vsn([H|T], S=#xmerl_scanner{col = C},Delim, Acc) when H >= $0, H =< $9 ->
    bench_util:bump(xmerlscanner),
    xml_vsn(T, S#xmerl_scanner{col = C+1}, Delim, [H|Acc]);
xml_vsn([H|T], S=#xmerl_scanner{col = C}, Delim, Acc) ->
    case lists:member(H, "_.:-") of
        true ->
            bench_util:bump(xmerlscanner),
            xml_vsn(T, S#xmerl_scanner{col = C+1}, Delim, [H|Acc]);
        false ->
            ?fatal({invalid_vsn_char, H}, S)
    end.
