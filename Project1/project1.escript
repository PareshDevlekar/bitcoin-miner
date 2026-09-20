#!/usr/bin/env escript
%%! +A 4 -setcookie cop5615_project1

-mode(compile).

-define(DEFAULT_WORK_UNIT, 10000).
-define(COOKIE, cop5615_project1).
-define(SERVER_NAME, "project1_server").
-define(RECONNECT_MS, 2000).

main(["--self-test"]) -> self_test();
main([Argument]) ->
    case classify_argument(Argument) of
        {server, Difficulty} -> start_server(Difficulty);
        {worker, ServerIp} -> start_remote_worker(ServerIp);
        error -> usage("Argument must be a difficulty from 0 to 64 or an IPv4 address.")
    end;
main(_) -> usage("Expected exactly one argument.").

start_server(Difficulty) ->
    Gatorlink = required_gatorlink(),
    {ok, _} = application:ensure_all_started(crypto),
    LocalIp = local_ipv4(),
    start_distribution(?SERVER_NAME, LocalIp),
    WorkUnit = positive_env("PROJECT1_WORK_UNIT", ?DEFAULT_WORK_UNIT),
    WorkerCount = non_negative_env("PROJECT1_WORKERS",
                                   max(1, erlang:system_info(schedulers_online))),
    MaxCoins = non_negative_env("PROJECT1_MAX_COINS", infinity),
    Boss = spawn(fun() -> boss_loop(#{difficulty => Difficulty,
                                      gatorlink => Gatorlink,
                                      work_unit => WorkUnit,
                                      next_start => 0,
                                      coin_count => 0,
                                      max_coins => MaxCoins}) end),
    true = register(project1_boss, Boss),
    spawn_workers(WorkerCount, Boss),
    io:format(standard_error,
              "Server ~s mining with ~B local worker actors; work unit = ~B.~n"
              "Remote workers can connect with: ./project1.escript ~s~n",
              [atom_to_list(node()), WorkerCount, WorkUnit, LocalIp]),
    monitor_boss(Boss).

start_remote_worker(ServerIp) ->
    {ok, _} = application:ensure_all_started(crypto),
    LocalIp = local_ipv4(),
    Unique = integer_to_list(erlang:system_time(microsecond)),
    start_distribution("project1_worker_" ++ Unique, LocalIp),
    ServerNode = list_to_atom(?SERVER_NAME ++ "@" ++ ServerIp),
    connect_and_work(ServerNode).

connect_and_work(ServerNode) ->
    case net_kernel:connect_node(ServerNode) of
        true ->
            worker_loop({project1_boss, ServerNode}),
            connect_and_work(ServerNode);
        false ->
            timer:sleep(?RECONNECT_MS),
            connect_and_work(ServerNode)
    end.

start_distribution(Name, Ip) ->
    _ = os:cmd("epmd -daemon"),
    NodeName = list_to_atom(Name ++ "@" ++ Ip),
    case net_kernel:start([NodeName, longnames]) of
        {ok, _Pid} -> erlang:set_cookie(node(), ?COOKIE);
        {error, {already_started, _Pid}} -> erlang:set_cookie(node(), ?COOKIE);
        {error, Reason} ->
            io:format(standard_error, "Could not start Erlang distribution: ~p~n", [Reason]),
            halt(1)
    end.

spawn_workers(Count, Boss) ->
    [spawn(fun() -> worker_loop(Boss) end) || _ <- lists:seq(1, Count)],
    ok.

monitor_boss(Boss) ->
    Ref = erlang:monitor(process, Boss),
    receive
        {'DOWN', Ref, process, Boss, normal} -> halt(0);
        {'DOWN', Ref, process, Boss, Reason} ->
            io:format(standard_error, "Boss stopped: ~p~n", [Reason]),
            halt(1)
    end.

boss_loop(State = #{difficulty := Difficulty,
                    gatorlink := Gatorlink,
                    work_unit := WorkUnit,
                    next_start := NextStart}) ->
    receive
        {request_work, Worker} when is_pid(Worker) ->
            Worker ! {work, Difficulty, Gatorlink, NextStart, WorkUnit},
            boss_loop(State#{next_start := NextStart + WorkUnit});
        {coin, Input, Hash} ->
            io:format("~s\t~s~n", [Input, Hash]),
            NewCount = maps:get(coin_count, State) + 1,
            maybe_continue(State#{coin_count := NewCount});
        _Unexpected -> boss_loop(State)
    end.

maybe_continue(State = #{max_coins := infinity}) -> boss_loop(State);
maybe_continue(#{coin_count := Count, max_coins := Max}) when Count >= Max -> ok;
maybe_continue(State) -> boss_loop(State).

worker_loop(Boss) ->
    monitor_node_if_remote(Boss),
    Boss ! {request_work, self()},
    receive
        {work, Difficulty, Gatorlink, Start, Count} ->
            mine_range(Boss, Difficulty, Gatorlink, Start, Count),
            worker_loop(Boss);
        {nodedown, _ServerNode} -> ok
    after 10000 -> ok
    end.

monitor_node_if_remote({_RegisteredName, ServerNode}) -> monitor_node(ServerNode, true);
monitor_node_if_remote(_LocalBossPid) -> ok.

mine_range(_Boss, _Difficulty, _Gatorlink, _Candidate, 0) -> ok;
mine_range(Boss, Difficulty, Gatorlink, Candidate, Remaining) ->
    Input = Gatorlink ++ ";" ++ integer_to_list(Candidate),
    Digest = crypto:hash(sha256, Input),
    case has_leading_zeroes(Digest, Difficulty) of
        true -> Boss ! {coin, Input, hex(Digest)};
        false -> ok
    end,
    mine_range(Boss, Difficulty, Gatorlink, Candidate + 1, Remaining - 1).

has_leading_zeroes(_Digest, 0) -> true;
has_leading_zeroes(Digest, Difficulty) when Difficulty >= 1, Difficulty =< 64 ->
    FullBytes = Difficulty div 2,
    HasHalfByte = Difficulty rem 2,
    <<Prefix:FullBytes/binary, Rest/binary>> = Digest,
    Prefix =:= <<0:(FullBytes * 8)>> andalso half_byte_is_zero(Rest, HasHalfByte).

half_byte_is_zero(_Rest, 0) -> true;
half_byte_is_zero(<<Byte, _/binary>>, 1) -> (Byte band 16#F0) =:= 0;
half_byte_is_zero(<<>>, 1) -> false.

hex(Binary) -> binary_to_list(binary:encode_hex(Binary, lowercase)).
sha256_hex(Text) -> hex(crypto:hash(sha256, Text)).

classify_argument(Text) ->
    case parse_difficulty(Text) of
        {ok, Difficulty} -> {server, Difficulty};
        error ->
            case inet:parse_ipv4_address(Text) of
                {ok, _Address} -> {worker, Text};
                {error, einval} -> error
            end
    end.

parse_difficulty(Text) ->
    try list_to_integer(Text) of
        Difficulty when Difficulty >= 0, Difficulty =< 64 -> {ok, Difficulty};
        _ -> error
    catch error:badarg -> error
    end.

required_gatorlink() ->
    case os:getenv("GATORLINK") of
        false -> usage("Set GATORLINK to one group member's UF username first.");
        "" -> usage("GATORLINK cannot be empty.");
        Value -> Value
    end.

positive_env(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        Text ->
            try list_to_integer(Text) of
                Value when Value > 0 -> Value;
                _ -> Default
            catch error:badarg -> Default end
    end.

non_negative_env(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        Text ->
            try list_to_integer(Text) of
                Value when Value >= 0 -> Value;
                _ -> Default
            catch error:badarg -> Default end
    end.

local_ipv4() ->
    case inet:getifaddrs() of
        {ok, Interfaces} ->
            Addresses = [Address || {_Name, Options} <- Interfaces,
                                    {addr, Address = {A, B, C, D}} <- Options,
                                    Address =/= {127, 0, 0, 1},
                                    A >= 0, B >= 0, C >= 0, D >= 0],
            case Addresses of
                [Address | _] -> inet:ntoa(Address);
                [] -> "127.0.0.1"
            end;
        {error, _} -> "127.0.0.1"
    end.

self_test() ->
    {ok, _} = application:ensure_all_started(crypto),
    Expected = "fb4431b6a2df71b6cbad961e08fa06ee6fff47e3bc14e977f4b2ea57caee48a4",
    Expected = sha256_hex("COP5615 is a boring class"),
    {server, 4} = classify_argument("4"),
    {worker, "10.22.13.155"} = classify_argument("10.22.13.155"),
    error = classify_argument("not-an-address"),
    true = has_leading_zeroes(<<0, 16#0F, 1:240>>, 3),
    false = has_leading_zeroes(<<0, 16#10, 1:240>>, 3),
    io:format("All self-tests passed.~n").

usage(Message) ->
    io:format(standard_error,
              "~s~nServer: GATORLINK=your_id ./project1.escript <leading-zeroes>~n"
              "Worker: ./project1.escript <server-ipv4-address>~n", [Message]),
    halt(2).
