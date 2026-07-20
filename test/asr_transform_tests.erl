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
