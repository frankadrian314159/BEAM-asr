-module(asr_transform_tests).
-include_lib("eunit/include/eunit.hrl").

%% ---------------------------------------------------------------------
%% Positive cases: functional equivalence between the plain fixture and
%% its ASR-transformed twin, plus a structural check (via parse_transform
%% applied directly to parsed Forms) that qualification actually fired -
%% i.e. that the twin's own arity really did change, not just that the
%% two happen to compute the same answer by coincidence.
%% ---------------------------------------------------------------------

full_reconstruction_test() ->
    ?assertEqual(fixture_full_reconstruction:run(500),
                 fixture_full_reconstruction_asr:run(500)),
    assert_qualified(fixture_full_reconstruction, loop, 3, 4).

partial_update_test() ->
    ?assertEqual(fixture_partial_update:run(500),
                 fixture_partial_update_asr:run(500)),
    assert_qualified(fixture_partial_update, loop, 3, 4).

passthrough_test() ->
    ?assertEqual(fixture_passthrough:run(500),
                 fixture_passthrough_asr:run(500)),
    assert_qualified(fixture_passthrough, loop, 3, 4).

guards_test() ->
    ?assertEqual(fixture_guards:run(12345),
                 fixture_guards_asr:run(12345)),
    assert_qualified(fixture_guards, loop, 3, 4).

%% Record field defaults (v1.4, Category A from the corpus study): an
%% entry call may omit a field that has a declared (or Erlang's own
%% implicit `undefined`) default - found via digraph:set_type/2 in
%% Erlang/OTP's stdlib, which declines under the old exact-match rule.
default_field_test() ->
    ?assertEqual(fixture_default_field:run(500), fixture_default_field_asr:run(500)),
    assert_qualified(fixture_default_field, loop, 3, 6).

%% Base-case continuation handoff (v1.4, Category B from the corpus
%% study): the base case hands the accumulator to another function
%% instead of returning it bare - found via inets/httpc.erl's
%% header_record/4 and throughout xmerl_scan.erl.
base_handoff_test() ->
    ?assertEqual(fixture_base_handoff:run(500), fixture_base_handoff_asr:run(500)),
    assert_qualified(fixture_base_handoff, loop, 3, 4).

%% Head-alias pattern (v1.5, Category D from the corpus study): the
%% clause's own pattern binds the whole accumulator AND destructures a
%% field, right in the head (`P=#pt{tag=T}`) - found via xmerl_scan.erl's
%% `S=#xmerl_scanner{col=C}` idiom and httpc.erl's validate_headers/3.
alias_pattern_test() ->
    ?assertEqual(fixture_alias_pattern:run(500), fixture_alias_pattern_asr:run(500)),
    assert_qualified(fixture_alias_pattern, loop, 3, 5).

%% Hoisted intermediate binding (v1.5, Category F narrow slice): the
%% reconstruction happens in an intermediate statement rather than
%% directly at the tail call's own argument position - mirrors
%% xmerl_scan.erl's `?bump_col(N)` macro.
hoisted_binding_test() ->
    ?assertEqual(fixture_hoisted_binding:run(500), fixture_hoisted_binding_asr:run(500)),
    assert_qualified(fixture_hoisted_binding, loop, 3, 4).

%% Update-expression transparency (v1.6): a base clause whose whole body
%% is a case expression, using the accumulator bare in one branch and as
%% an update expression's own base in another - mirrors xmerl_scan.erl's
%% xml_vsn/4 and httpc.erl's validate_headers/3.
case_wrapped_base_test() ->
    ?assertEqual(fixture_case_wrapped_base:run(500), fixture_case_wrapped_base_asr:run(500)),
    assert_qualified(fixture_case_wrapped_base, loop, 3, 4).

%% Guard-converted alias field (v1.6, Category D full slice): a ground
%% literal sub-pattern with no wildcards or variable bindings anywhere
%% inside it (`#pt{tag=fixed}`) converts to an ordinary scalar pattern
%% var plus an added `=:=` guard - mirrors httpc.erl's
%% `RequestHeaders = #http_request_h{host=undefined}`.
alias_guard_test() ->
    ?assertEqual(fixture_alias_guard:run(500), fixture_alias_guard_asr:run(500)),
    assert_qualified(fixture_alias_guard, loop, 3, 5).

%% Indirect entry construction (v1.6, Category E): the entry call's
%% accumulator argument is a bare variable - here wrapper/2's own
%% parameter, forwarded through - rather than a literal construction at
%% the call site. Mirrors xmerl_scan.erl's `strip/2 -> strip/3` and
%% `scan_system_literal/2 -> scan_system_literal/4`.
indirect_entry_test() ->
    ?assertEqual(fixture_indirect_entry:run(500), fixture_indirect_entry_asr:run(500)),
    assert_qualified(fixture_indirect_entry, loop, 3, 4).

%% Indirect entry construction, update-expression shape (v1.6, Category
%% E): the entry call's accumulator argument is an update expression,
%% not a bare variable or literal construction - mirrors xmerl_scan.erl's
%% `scan_xml_vsn/2 -> xml_vsn(T, S#xmerl_scanner{col=...}, H, [])`.
indirect_entry_update_test() ->
    ?assertEqual(fixture_indirect_entry_update:run(500), fixture_indirect_entry_update_asr:run(500)),
    assert_qualified(fixture_indirect_entry_update, loop, 3, 4).

%% Embedded self-call inside a case-wrapped base clause (v1.6 fix,
%% found while benchmarking xmerl_scan.erl's real xml_vsn/4): the
%% clause's own trailing form is a case expression, not a literal tail
%% call, so it's classified base - but one of its branches is itself a
%% recursive call whose own accumulator argument (an update expression)
%% still needs splicing, exactly like a genuine external entry call.
case_embedded_selfcall_test() ->
    ?assertEqual(fixture_case_embedded_selfcall:run(500), fixture_case_embedded_selfcall_asr:run(500)),
    assert_qualified(fixture_case_embedded_selfcall, loop, 3, 4).

%% Interprocedural inlining (v1.1): the reconstruction lives in a
%% separate one-level-inlinable helper function, not literally in the
%% tail call's own argument.
inline_with_bindings_test() ->
    ?assertEqual(fixture_inline:run(500), fixture_inline_asr:run(500)),
    assert_qualified(fixture_inline, loop, 3, 6).

inline_direct_test() ->
    ?assertEqual(fixture_inline_direct:run(500), fixture_inline_direct_asr:run(500)),
    assert_qualified(fixture_inline_direct, loop, 3, 4).

%% Multi-accumulator (v1.2): two record accumulators threaded through the
%% same recursion simultaneously.
multi_symmetric_test() ->
    ?assertEqual(fixture_multi_symmetric:run(500), fixture_multi_symmetric_asr:run(500)),
    assert_qualified(fixture_multi_symmetric, loop, 4, 6).

multi_asymmetric_test() ->
    ?assertEqual(fixture_multi_asymmetric:run(500), fixture_multi_asymmetric_asr:run(500)),
    assert_qualified(fixture_multi_asymmetric, loop, 4, 7).

%% ---------------------------------------------------------------------
%% Negative / abort-safe cases: the transform must decline cleanly and
%% leave the function's original arity and behavior completely intact.
%% ---------------------------------------------------------------------

exported_helper_declines_test() ->
    Got = fixture_exported_helper:loop(mk_pt(0, 0), 0, 500),
    ?assertEqual({500, 1000}, {pt_a(Got), pt_b(Got)}),
    assert_declined(fixture_exported_helper).

bad_callsite_declines_test() ->
    R1 = fixture_bad_callsite:run(500),
    ?assertEqual({500, 1000}, {pt_a(R1), pt_b(R1)}),
    ?assertEqual(undefined, fixture_bad_callsite:weird()),
    assert_declined(fixture_bad_callsite).

intra_clause_case_declines_test() ->
    R = fixture_intra_clause_case:run(500),
    %% 250 even steps (+1/+2) and 250 odd steps (+3/+4) over 500 iterations
    ?assertEqual({250 * 1 + 250 * 3, 250 * 2 + 250 * 4}, {pt_a(R), pt_b(R)}),
    assert_declined(fixture_intra_clause_case).

name_collision_declines_test() ->
    R = fixture_name_collision:run(500),
    ?assertEqual({500, 1000}, {pt_a(R), pt_b(R)}),
    assert_declined(fixture_name_collision).

inline_guarded_helper_declines_test() ->
    R = fixture_inline_guarded_helper:run(500),
    ?assertEqual({500, 1000}, {pt_a(R), pt_b(R)}),
    assert_declined(fixture_inline_guarded_helper).

inline_multiclause_helper_declines_test() ->
    R = fixture_inline_multiclause_helper:run(500),
    ?assertEqual({500, 1000}, {pt_a(R), pt_b(R)}),
    assert_declined(fixture_inline_multiclause_helper).

inline_nested_declines_test() ->
    R = fixture_inline_nested:run(500),
    ?assertEqual({500, 1000}, {pt_a(R), pt_b(R)}),
    assert_declined(fixture_inline_nested).

inline_temp_collision_declines_test() ->
    R = fixture_inline_temp_collision:run(500),
    ?assertEqual({500, 0}, {pt_a(R), pt_b(R)}),
    assert_declined(fixture_inline_temp_collision).

multi_scalar_collision_declines_test() ->
    R = fixture_multi_scalar_collision:run(500),
    ?assertEqual(1000, R),
    assert_declined(fixture_multi_scalar_collision).

base_double_bare_declines_test() ->
    R = fixture_base_double_bare:run(500),
    ?assertEqual({{pt, 500.0, 1000.0}, {pt, 500.0, 1000.0}}, R),
    assert_declined(fixture_base_double_bare).

alias_nested_declines_test() ->
    R = fixture_alias_nested_declines:run(500),
    ?assertEqual({pt, 500.0, 1000.0, {external, {entity, foo}}}, R),
    assert_declined(fixture_alias_nested_declines).

hoisted_binding_escapes_declines_test() ->
    R = fixture_hoisted_binding_escapes_declines:run(500),
    ?assertEqual({pt, 500.0, 1000.0}, R),
    assert_declined(fixture_hoisted_binding_escapes_declines).

indirect_entry_expr_declines_test() ->
    R = fixture_indirect_entry_expr_declines:run(500),
    ?assertEqual({pt, 500.0, 1000.0}, R),
    assert_declined(fixture_indirect_entry_expr_declines).

%% ---------------------------------------------------------------------
%% Helpers
%% ---------------------------------------------------------------------

%% Record #pt{a,b} is private to each fixture module; read fields
%% positionally instead of via -record here.
pt_a(Rec) -> element(2, Rec).
pt_b(Rec) -> element(3, Rec).
mk_pt(A, B) -> {pt, A, B}.

%% Re-runs the transform directly against the module's own parsed source
%% and checks that Name/OldArity was rewritten to Name/NewArity.
assert_qualified(Module, Name, OldArity, NewArity) ->
    Forms = parse_own_source(Module),
    Forms1 = asr_transform:parse_transform(Forms, []),
    ?assertNot(has_function(Forms1, Name, OldArity)),
    ?assert(has_function(Forms1, Name, NewArity)).

%% Re-runs the transform directly and checks the module's forms are
%% completely unchanged (decline must never partially rewrite).
assert_declined(Module) ->
    Forms = parse_own_source(Module),
    Forms1 = asr_transform:parse_transform(Forms, []),
    ?assertEqual(strip_file_attr(Forms), strip_file_attr(Forms1)).

parse_own_source(Module) ->
    Path = source_path(Module),
    {ok, Forms} = epp:parse_file(Path, [{includes, [filename:dirname(Path)]}]),
    Forms.

source_path(Module) ->
    Dir = filename:dirname(?FILE),
    filename:join(Dir, atom_to_list(Module) ++ ".erl").

has_function(Forms, Name, Arity) ->
    lists:any(fun({function, _, N, A, _}) -> N =:= Name andalso A =:= Arity;
                 (_) -> false
              end, Forms).

%% epp re-parses on every call, so line/anno-identical Forms compare equal
%% except for the file attribute's own path, which is irrelevant here.
strip_file_attr(Forms) ->
    [F || F <- Forms, element(1, F) =/= attribute orelse element(3, F) =/= file].
