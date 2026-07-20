%% Corpus scan driver. Reads manifest.txt (path domain-tag per line,
%% relative to the OTP lib root), runs the two-pass scan over every
%% file, and prints a summary + per-candidate detail report.
-module(run_corpus_scan).
-export([main/1]).

main([OtpLibRoot, ManifestPath]) ->
    Entries = read_manifest(ManifestPath),
    Results = [scan_one(OtpLibRoot, Path, Domain) || {Path, Domain} <- Entries],
    print_summary(Results),
    print_detail(Results),
    ok.

read_manifest(Path) ->
    {ok, Bin} = file:read_file(Path),
    Lines = binary:split(Bin, [<<"\n">>, <<"\r\n">>], [global]),
    lists:filtermap(
      fun(Line0) ->
              Line = string:trim(binary_to_list(Line0)),
              case Line of
                  "" -> false;
                  [$# | _] -> false;
                  _ ->
                      [P, D] = string:split(Line, " "),
                      {true, {P, D}}
              end
      end, Lines).

scan_one(OtpLibRoot, RelPath, Domain) ->
    Path = filename:join(OtpLibRoot, RelPath),
    Dir = filename:dirname(Path),
    AppSrcDir = Dir,
    AppRoot = find_app_root(Dir),
    IncludeDirs = lists:usort([AppSrcDir, filename:join(AppRoot, "include"),
                                filename:join(AppRoot, "src")]),
    Loc = count_loc(Path),
    case asr_candidate_scanner:scan_file(Path, IncludeDirs) of
        {ok, Forms, Candidates} ->
            RecordCands = [C || C <- Candidates,
                                 maps:get(kind, C) =:= record_strong orelse
                                 maps:get(kind, C) =:= record_weak],
            Graded = [{C, asr_gate_check:qualifies(Forms, C)} || C <- RecordCands],
            #{path => RelPath, domain => Domain, status => ok, loc => Loc,
              candidates => Candidates, graded => Graded};
        {error, Reason} ->
            #{path => RelPath, domain => Domain, status => {error, Reason}, loc => Loc,
              candidates => [], graded => []}
    end.

%% Walks up from a src/ dir to find the OTP application root (the
%% directory containing src/, include/, ebin/ as siblings).
find_app_root(Dir) ->
    case filename:basename(Dir) of
        "src" -> filename:dirname(Dir);
        _ ->
            Parent = filename:dirname(Dir),
            case Parent of
                Dir -> Dir;
                _ -> find_app_root(Parent)
            end
    end.

count_loc(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> length(binary:split(Bin, <<"\n">>, [global]));
        {error, _} -> 0
    end.

print_summary(Results) ->
    io:format("~n=== Per-file summary ===~n"),
    io:format("~-45s ~-22s ~6s ~5s ~5s ~5s ~5s ~5s ~6s~n",
              ["File", "Domain", "LOC", "Loop", "RecS", "RecW", "Map", "Coll", "Qual"]),
    lists:foreach(fun print_file_row/1, Results),
    TotalLoc = lists:sum([maps:get(loc, R) || R <- Results]),
    OkResults = [R || R <- Results, maps:get(status, R) =:= ok],
    AllCands = lists:append([maps:get(candidates, R) || R <- OkResults]),
    LoopSites = length(lists:usort([{maps:get(path,R), maps:get(name,C), maps:get(arity,C)}
                                     || R <- OkResults, C <- maps:get(candidates, R)])),
    CountKind = fun(K) -> length([C || C <- AllCands, maps:get(kind, C) =:= K]) end,
    AllGraded = lists:append([maps:get(graded, R) || R <- OkResults]),
    Qualified = length([1 || {_, true} <- AllGraded]),
    Declined = length([1 || {_, false} <- AllGraded]),
    Unknown = length([1 || {_, unknown} <- AllGraded]),
    io:format("~n=== Totals ===~n"),
    io:format("Files scanned OK: ~p / ~p~n", [length(OkResults), length(Results)]),
    io:format("Total LOC: ~p (~.2f KLOC)~n", [TotalLoc, TotalLoc / 1000]),
    io:format("Tail-self-recursive functions (loop sites, unique): ~p~n", [LoopSites]),
    io:format("Candidate positions by kind: record_strong=~p record_weak=~p map=~p "
              "collection=~p scalar=~p other=~p~n",
              [CountKind(record_strong), CountKind(record_weak), CountKind(map_kind),
               CountKind(collection_kind), CountKind(scalar_kind), CountKind(other_kind)]),
    io:format("Record-shaped (strong+weak) positions: ~p~n",
              [CountKind(record_strong) + CountKind(record_weak)]),
    io:format("Gate-faithful qualification: qualified=~p declined=~p unknown=~p~n",
              [Qualified, Declined, Unknown]).

print_file_row(#{status := {error, Reason}, path := Path, domain := Domain, loc := Loc}) ->
    io:format("~-45s ~-22s ~6p PARSE ERROR: ~p~n", [Path, Domain, Loc, Reason]);
print_file_row(#{status := ok, path := Path, domain := Domain, loc := Loc,
                  candidates := Candidates, graded := Graded}) ->
    LoopSites = length(lists:usort([{maps:get(name, C), maps:get(arity, C)} || C <- Candidates])),
    RecS = length([C || C <- Candidates, maps:get(kind, C) =:= record_strong]),
    RecW = length([C || C <- Candidates, maps:get(kind, C) =:= record_weak]),
    MapC = length([C || C <- Candidates, maps:get(kind, C) =:= map_kind]),
    CollC = length([C || C <- Candidates, maps:get(kind, C) =:= collection_kind]),
    Qual = length([1 || {_, true} <- Graded]),
    io:format("~-45s ~-22s ~6p ~5p ~5p ~5p ~5p ~5p ~6p~n",
              [Path, Domain, Loc, LoopSites, RecS, RecW, MapC, CollC, Qual]).

print_detail(Results) ->
    io:format("~n=== Record-shaped candidate detail (for manual false-positive review) ===~n"),
    lists:foreach(
      fun(#{status := ok, path := Path, graded := Graded}) ->
              lists:foreach(
                fun({C, Verdict}) ->
                        io:format("~s :: ~p/~p pos=~p kind=~p recursive_clauses=~p/~p -> ~p~n",
                                  [Path, maps:get(name, C), maps:get(arity, C), maps:get(pos, C),
                                   maps:get(kind, C), maps:get(recursive_clauses, C),
                                   maps:get(total_clauses, C), Verdict])
                end, Graded);
         (_) -> ok
      end, Results).
