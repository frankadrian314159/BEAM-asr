-module(bench_strip_asr).
-compile({parse_transform, asr_transform}).
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

fatal(Reason, S) -> exit({fatal, {Reason, {line, S#xmerl_scanner.line}}}).

run(N) ->
    Input = lists:duplicate(N, $\s) ++ "X",
    S0 = #xmerl_scanner{continuation_fun = unused},
    strip(Input, S0, all).

strip(Str,S) ->
    strip(Str,S,all).

strip([], S=#xmerl_scanner{continuation_fun = F},_) ->
    ?dbg("cont()... stripping whitespace~n", []),
    F(fun(MoreBytes, S1) -> strip(MoreBytes, S1) end,
      fun(S1) -> {[], [], S1} end,
      S);
strip("\s" ++ T, S=#xmerl_scanner{col = C},Lim) ->
    strip(T, S#xmerl_scanner{col = C+1},Lim);
strip("\t" ++ _T, S ,no_tab) ->
    ?fatal({error,{no_tab_allowed}},S);
strip("\t" ++ T, S=#xmerl_scanner{col = C},Lim) ->
    strip(T, S#xmerl_scanner{col = expand_tab(C)},Lim);
strip("\n" ++ T, S=#xmerl_scanner{line = L},Lim) ->
    strip(T, S#xmerl_scanner{line = L+1, col = 1},Lim);
strip("\r\n" ++ T, S=#xmerl_scanner{line = L},Lim) ->
    %% CR followed by LF is read as a single LF
    strip(T, S#xmerl_scanner{line = L+1, col = 1},Lim);
strip("\r" ++ T, S=#xmerl_scanner{line = L},Lim) ->
    %% CR not followed by LF is read as a LF
    strip(T, S#xmerl_scanner{line = L+1, col = 1},Lim);
strip(Str, S,_Lim) ->
    {[], Str, S}.

expand_tab(Col) ->
    Rem = (Col-1) rem 8,
    _NewCol = Col + 8 - Rem.
