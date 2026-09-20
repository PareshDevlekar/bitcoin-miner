#!/usr/bin/env escript
%%! +A 4

-mode(compile).

-define(WORK_UNIT, 10000).

main([DifficultyText]) ->
    case parse_difficulty(DifficultyText) of
        {ok, Difficulty} ->
            case os:getenv("GATORLINK") of
                false ->
                    usage("Set the GATORLINK environment variable first.");
                Gatorlink ->
                    start_local(Difficulty, Gatorlink)
            end;
        error ->
            usage("Difficulty must be a non-negative integer.")
    end;
main(_) ->
    usage("Expected exactly one argument.").

start_local(Difficulty, Gatorlink) ->
    crypto:start(),
    WorkerCount = max(1, erlang:system_info(schedulers_online)),
    Boss = spawn(fun() -> boss_loop(Difficulty, Gatorlink, 0) end),
    [spawn(fun() -> worker_loop(Boss) end)
     || _ <- lists:seq(1, WorkerCount)],
    io:format(standard_error,
              "Mining with ~B worker actors; work unit = ~B. Press Ctrl-C to stop.~n",
              [WorkerCount, ?WORK_UNIT]),
    monitor_boss(Boss).

monitor_boss(Boss) ->
    Ref = erlang:monitor(process, Boss),
    receive
        {'DOWN', Ref, process, Boss, Reason} ->
            io:format(standard_error, "Boss stopped: ~p~n", [Reason]),
            halt(1)
    end.

boss_loop(Difficulty, Gatorlink, NextStart) ->
    receive
        {request_work, Worker} ->
            Worker ! {work, Difficulty, Gatorlink, NextStart, ?WORK_UNIT},
            boss_loop(Difficulty, Gatorlink, NextStart + ?WORK_UNIT);
        {coin, Input, Hash} ->
            io:format("~s\t~s~n", [Input, Hash]),
            boss_loop(Difficulty, Gatorlink, NextStart)
    end.

worker_loop(Boss) ->
    Boss ! {request_work, self()},
    receive
        {work, Difficulty, Gatorlink, Start, Count} ->
            mine_range(Boss, Difficulty, Gatorlink, Start, Count),
            worker_loop(Boss)
    end.

mine_range(_Boss, _Difficulty, _Gatorlink, _Candidate, 0) ->
    ok;
mine_range(Boss, Difficulty, Gatorlink, Candidate, Remaining) ->
    Input = Gatorlink ++ ";" ++ integer_to_list(Candidate),
    Digest = crypto:hash(sha256, Input),
    case has_leading_zeroes(Digest, Difficulty) of
        true -> Boss ! {coin, Input, hex(Digest)};
        false -> ok
    end,
    mine_range(Boss, Difficulty, Gatorlink, Candidate + 1, Remaining - 1).

has_leading_zeroes(_Digest, 0) ->
    true;
has_leading_zeroes(Digest, Difficulty) ->
    FullBytes = Difficulty div 2,
    HasHalfByte = Difficulty rem 2,
    case Digest of
        <<Prefix:FullBytes/binary, Rest/binary>> ->
            PrefixIsZero = Prefix =:= <<0:(FullBytes * 8)>>,
            PrefixIsZero andalso half_byte_is_zero(Rest, HasHalfByte)
    end.

half_byte_is_zero(_Rest, 0) ->
    true;
half_byte_is_zero(<<Byte, _/binary>>, 1) ->
    (Byte band 16#F0) =:= 0;
half_byte_is_zero(<<>>, 1) ->
    false.

hex(Binary) ->
    binary_to_list(binary:encode_hex(Binary, lowercase)).

parse_difficulty(Text) ->
    try list_to_integer(Text) of
        Difficulty when Difficulty >= 0, Difficulty =< 64 -> {ok, Difficulty};
        _ -> error
    catch
        error:badarg -> error
    end.

usage(Message) ->
    io:format(standard_error,
              "~s~nUsage: GATORLINK=your_id ./project1.escript <leading-zeroes>~n",
              [Message]),
    halt(2).

