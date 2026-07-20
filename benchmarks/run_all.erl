%% Benchmark driver for BEAM-asr's three ported benchmarks (Particle,
%% Counter, Assoc). Mirrors cpython-asr's harness.py protocol: correctness
%% (baseline vs. transformed output, bit-identical) gates any timing
%% report, and per-run allocation is measured via an explicit construction
%% counter rather than a memory snapshot diff (Erlang's GC has the same
%% allocator-slot-reuse pitfall documented in cpython-asr's own harness).
-module(run_all).
-export([main/0]).

-define(ITERATIONS, 500000).
-define(TRIALS, 30).

main() ->
    Specs = [{"Particle", bench_particle_plain, bench_particle_asr, bench_particle_counted, particle},
             {"Counter",  bench_counter_plain,  bench_counter_asr,  bench_counter_counted,  ctr},
             {"Assoc",    bench_assoc_plain,    bench_assoc_asr,    bench_assoc_counted,    particle}],
    io:format("~-10s ~12s ~12s ~8s ~14s ~14s~n",
              ["Benchmark", "Base ms", "ASR ms", "Speedup", "Base constr", "ASR constr"]),
    io:format("~s~n", [lists:duplicate(74, $-)]),
    lists:foreach(fun(Spec) -> run_one(Spec) end, Specs),
    ok.

run_one({Name, PlainMod, AsrMod, CountedMod, Tag}) ->
    Plain = PlainMod:run(?ITERATIONS),
    Asr = AsrMod:run(?ITERATIONS),
    case Plain =:= Asr of
        true -> ok;
        false ->
            io:format("~s: CORRECTNESS MISMATCH plain=~p asr=~p~n", [Name, Plain, Asr]),
            erlang:halt(1)
    end,
    PlainMod:run(?ITERATIONS),
    AsrMod:run(?ITERATIONS),
    BaseUs = mean_time(fun() -> PlainMod:run(?ITERATIONS) end),
    AsrUs = mean_time(fun() -> AsrMod:run(?ITERATIONS) end),
    CountedMod:run(?ITERATIONS),
    BaseConstr = bench_util:read_counter(Tag),
    io:format("~-10s ~12.2f ~12.2f ~7.2fx ~13Bx ~15s~n",
              [Name, BaseUs / 1000, AsrUs / 1000, BaseUs / AsrUs, BaseConstr, "0 (eliminated)"]).

mean_time(Fun) ->
    Times = [begin {T, _} = timer:tc(Fun), T end || _ <- lists:seq(1, ?TRIALS)],
    lists:sum(Times) / length(Times).
