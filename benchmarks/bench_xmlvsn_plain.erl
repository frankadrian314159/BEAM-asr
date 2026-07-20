%% ASR Benchmark: xmerl_scan:xml_vsn/4 and its scan_xml_vsn/2 entry
%% wrapper, extracted verbatim from Erlang/OTP 28.5's
%% lib/xmerl/src/xmerl_scan.erl (lines 1164-1193) - one of the real
%% corpus-study "unlocked loops" (v1.6: update-expression transparency
%% in a case-wrapped clause, a head-alias pattern in the recursive
%% clauses, and an update-expression entry call from scan_xml_vsn/2).
%%
%% #xmerl_scanner{} and #xmerl_fun_states{} are copied verbatim from
%% lib/xmerl/include/xmerl.hrl (lines 146-194) - the full 40-field
%% scanner state record, so this benchmark measures the real
%% reconstruction cost the corpus study found, not a toy record.
%%
%% ?dbg/?fatal/fatal_fun/1/fatal/2 are minimal stand-ins for the real
%% macros/helpers, only ever reached on an out-of-input continuation or
%% an invalid-character error - neither occurs on this benchmark's
%% finite, valid-character input, so their exact bodies never affect
%% the measured loop.
-module(bench_xmlvsn_plain).
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
    Input = [$"] ++ lists:duplicate(N, $1) ++ [$"],
    %% A plain atom placeholder, not a fun: the continuation_fun field is
    %% only ever read (never called) on this benchmark's finite input,
    %% and using an atom instead of a fun keeps correctness comparisons
    %% between plain/asr straightforward (funs compare by identity, so
    %% two separately-compiled modules' closures would never be equal
    %% even when everything else about the result matches).
    S0 = #xmerl_scanner{continuation_fun = unused},
    scan_xml_vsn(Input, S0).

%% --- verbatim from xmerl_scan.erl:1164-1193 ---
scan_xml_vsn([], S=#xmerl_scanner{continuation_fun = F}) ->
    ?dbg("cont()...~n", []),
    F(fun(MoreBytes, S1) -> scan_xml_vsn(MoreBytes, S1) end,
      fatal_fun(unexpected_end),
      S);
scan_xml_vsn([H|T], S) when H==$"; H==$'->
    xml_vsn(T, S#xmerl_scanner{col = S#xmerl_scanner.col+1}, H, []).

%% xml_vsn/4's own `[]` (out-of-input continuation) clause is
%% deliberately omitted here: it self-calls xml_vsn/4 from inside a
%% nested fun closure, a shape the rewrite pass doesn't reach (distinct
%% from the documented "different qualifying function nested in a
%% clause body" limitation - this is the SAME function, self-referential,
%% inside a closure within a non-recursive clause). It's unreachable on
%% this benchmark's finite, always-terminated input regardless.
xml_vsn([H|T], S=#xmerl_scanner{col = C}, H, Acc) ->
    {lists:reverse(Acc), T, S#xmerl_scanner{col = C+1}};
xml_vsn([H|T], S=#xmerl_scanner{col = C},Delim, Acc) when H >= $a, H =< $z ->
    xml_vsn(T, S#xmerl_scanner{col = C+1}, Delim, [H|Acc]);
xml_vsn([H|T], S=#xmerl_scanner{col = C},Delim, Acc) when H >= $A, H =< $Z ->
    xml_vsn(T, S#xmerl_scanner{col = C+1}, Delim, [H|Acc]);
xml_vsn([H|T], S=#xmerl_scanner{col = C},Delim, Acc) when H >= $0, H =< $9 ->
    xml_vsn(T, S#xmerl_scanner{col = C+1}, Delim, [H|Acc]);
xml_vsn([H|T], S=#xmerl_scanner{col = C}, Delim, Acc) ->
    case lists:member(H, "_.:-") of
        true ->
            xml_vsn(T, S#xmerl_scanner{col = C+1}, Delim, [H|Acc]);
        false ->
            ?fatal({invalid_vsn_char, H}, S)
    end.
