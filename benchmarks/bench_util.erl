-module(bench_util).
-export([reset_counter/1, bump/1, read_counter/1, time_it/1]).

reset_counter(Tag) ->
    case ets:info(bench_counts) of
        undefined -> ets:new(bench_counts, [named_table, public, set]);
        _ -> ok
    end,
    ets:insert(bench_counts, {Tag, 0}).

bump(Tag) ->
    ets:update_counter(bench_counts, Tag, 1).

read_counter(Tag) ->
    ets:lookup_element(bench_counts, Tag, 2).

time_it(Fun) ->
    timer:tc(Fun).
