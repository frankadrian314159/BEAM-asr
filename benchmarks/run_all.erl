%% Benchmark driver for all 14 ported benchmarks (Particle/Counter/Assoc
%% from v1; Rotation/Biquad/Comoments/Lorenz/Mandelbrot/Projectile from
%% v1.1 inlining; Bounce/Clamp/Phase from v1.3 branch-as-guarded-clauses;
%% Kalman/Twobody from v1.2 multi-accumulator). Mirrors cpython-asr's
%% harness.py protocol: correctness (baseline vs. transformed output,
%% bit-identical) gates any timing report, and per-run allocation is
%% measured via an explicit construction counter rather than a memory
%% snapshot diff (Erlang's GC has the same allocator-slot-reuse pitfall
%% documented in cpython-asr's own harness). Tags is a list since a
%% multi-accumulator benchmark (Kalman) counts more than one record type,
%% and Twobody's two accumulators share one record type/tag.
-module(run_all).
-export([main/0]).

-define(ITERATIONS, 500000).
-define(TRIALS, 30).

main() ->
    Specs = [{"Particle",   bench_particle_plain,   bench_particle_asr,   bench_particle_counted,   [particle]},
             {"Counter",    bench_counter_plain,    bench_counter_asr,    bench_counter_counted,    [ctr]},
             {"Assoc",      bench_assoc_plain,      bench_assoc_asr,      bench_assoc_counted,      [particle]},
             {"Rotation",   bench_rotation_plain,   bench_rotation_asr,   bench_rotation_counted,   [rot]},
             {"Biquad",     bench_biquad_plain,     bench_biquad_asr,     bench_biquad_counted,     [biquad]},
             {"Comoments",  bench_comoments_plain,  bench_comoments_asr,  bench_comoments_counted,  [comoments]},
             {"Lorenz",     bench_lorenz_plain,     bench_lorenz_asr,     bench_lorenz_counted,     [lvec3]},
             {"Mandelbrot", bench_mandelbrot_plain, bench_mandelbrot_asr, bench_mandelbrot_counted, [cplx]},
             {"Projectile", bench_projectile_plain, bench_projectile_asr, bench_projectile_counted, [state3]},
             {"Bounce",     bench_bounce_plain,     bench_bounce_asr,     bench_bounce_counted,     [bounce]},
             {"Clamp",      bench_clamp_plain,      bench_clamp_asr,      bench_clamp_counted,      [point]},
             {"Phase",      bench_phase_plain,      bench_phase_asr,      bench_phase_counted,      [phase]},
             {"Kalman",     bench_kalman_plain,     bench_kalman_asr,     bench_kalman_counted,     [kstate, kcov]},
             {"Twobody",    bench_twobody_plain,    bench_twobody_asr,    bench_twobody_counted,    [vec2]}],
    io:format("~-11s ~12s ~12s ~8s ~14s ~15s~n",
              ["Benchmark", "Base ms", "ASR ms", "Speedup", "Base constr", "ASR constr"]),
    io:format("~s~n", [lists:duplicate(76, $-)]),
    lists:foreach(fun(Spec) -> run_one(Spec) end, Specs),
    ok.

run_one({Name, PlainMod, AsrMod, CountedMod, Tags}) ->
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
    BaseConstr = lists:sum([bench_util:read_counter(Tag) || Tag <- Tags]),
    io:format("~-11s ~12.2f ~12.2f ~7.2fx ~13Bx ~15s~n",
              [Name, BaseUs / 1000, AsrUs / 1000, BaseUs / AsrUs, BaseConstr, "0 (eliminated)"]).

mean_time(Fun) ->
    Times = [begin {T, _} = timer:tc(Fun), T end || _ <- lists:seq(1, ?TRIALS)],
    lists:sum(Times) / length(Times).
