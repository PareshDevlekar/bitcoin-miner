# COP5615 Project 1 — Bitcoin Miner

## Group members

- Paresh Devlekar — GatorLink: `paresh.devlekar`
- Omkar Salkade — GatorLink: `o.salkade`

## Overview

This project mines SHA-256 strings using Erlang actors. A boss actor owns the
global candidate counter and assigns non-overlapping ranges to workers. Each
worker hashes its range independently and sends successful coins to the boss.
Only the server's boss prints results, including results discovered by remote
workers.

The input string format is:

```text
paresh.devlekar;<candidate-number>
```

Every result is printed to standard output in the required format:

```text
input-string<TAB>lowercase-sha256-hash
```

Status information is written to standard error so it does not corrupt the
coin output.

## Requirements

- Erlang/OTP 24 or newer
- The server and workers must be able to reach each other over the network
- TCP port 4369 (EPMD) and Erlang distribution traffic must be permitted by the
  machines' firewalls

No third-party Erlang libraries are required.

## Run the server

The only argument is the required number of leading hexadecimal zeroes.
The server also starts one local worker actor per online Erlang scheduler.

```sh
cd Project1
chmod +x project1.escript
./project1.escript 4
```

The gatorlink prefix `paresh.devlekar` is built into the program. It can be
overridden with the optional `GATORLINK` environment variable, which is not
needed for normal use.

The server prints its IPv4 address at startup. It mines continuously until
stopped with `Ctrl-C`.

## Run a remote worker

Copy the `Project1` directory to another machine with Erlang installed, then
pass the server's displayed IPv4 address or its hostname:

```sh
cd Project1
chmod +x project1.escript
./project1.escript 10.22.13.155
```

The remote process is intentionally silent. It starts one worker actor per
online Erlang scheduler so the joining machine contributes all of its cores,
connects to the registered boss, and then each actor repeatedly requests a work
unit, mines it, and returns any coins. If the server is unavailable, or goes
away later, the worker retries every two seconds. All coins are printed by the
server.

## Actor model

- **Boss actor:** owns the next unassigned candidate number, assigns work units,
  receives coins, and prints results.
- **Local worker actors:** request ranges from the boss and hash candidates on
  the server's Erlang schedulers.
- **Remote worker actors:** use the same message protocol over Erlang
  distribution and can join while the server is already running.

No threads, shared mutable state, or non-actor parallelism are used. Candidate
ranges are assigned only by the boss, so two workers are never intentionally
given the same range.

## Work-unit size

The selected work unit is **1,000 candidate strings**. We compared 1,000,
10,000, and 50,000 candidates per assignment by mining 500 coins at difficulty
4 with 10 local worker actors. Each size was run three times to reduce the
effect of startup cost and run-to-run noise. The 1,000-candidate unit had the
lowest median real time. It also redistributes work most quickly when machines
with different speeds join or leave.

| Candidates per work unit | Trial 1 | Trial 2 | Trial 3 | Median |
| ---: | ---: | ---: | ---: | ---: |
| 1,000 | 4.81 s | 4.70 s | 4.67 s | **4.70 s** |
| 10,000 | 4.80 s | 4.76 s | 4.75 s | 4.76 s |
| 50,000 | 4.76 s | 4.66 s | 4.73 s | 4.73 s |

The three medians are close, so the measurements do not support claiming a
large throughput difference. They do show that the smaller unit's additional
actor messages did not reduce throughput in this implementation.

## Result for input 4

The following coins were produced by `./project1.escript 4`:

```text
paresh.devlekar;59548	0000acb76625374ba307f9cafbac9d75e3d93293550e5f8c6b81eb6eea1220ad
paresh.devlekar;176475	0000b09edbfc296bb07273339061d6e15f420d9c74adfea8531a3d25ed34d301
paresh.devlekar;179337	00005e34d3da0d26c53b81f88311688be13ca2e4a98794b5d6ca2920e1bf2149
paresh.devlekar;196515	00007f1ee04a4377b6a5b7667df5aba3a33375bda8db29fad500ab9f6693df77
paresh.devlekar;255977	0000d43c82e72a7875a6b9f899b85607938278b49813afeda325345d20710e58
```

## Running time and parallelism

The median 1,000-unit input-4 run used 10 local worker actors and stopped after
500 coins for a repeatable measurement:

```text
real 4.70
user 36.52
sys  0.51
```

The CPU-to-real-time ratio was `(36.52 + 0.51) / 4.70 = 7.88`, showing that
nearly eight CPU cores were used effectively during the input-4 run. A separate
longer difficulty-6 run measured `real 6.88`, `user 61.74`, and `sys 1.99`, for
a ratio of `9.26` on the 10-core machine.

For repeatable measurements, `PROJECT1_MAX_COINS` can stop the server after a
specified number of coins. This option is not needed for normal submission use:

```sh
/usr/bin/time -p env PROJECT1_MAX_COINS=500 ./project1.escript 4
```

## Coin with the most leading zeroes

The best coin found during the recorded runs had six leading zeroes:

```text
paresh.devlekar;52171206	00000038ffd9309658fcc09369c279630d110b446e959903ec6b61f882019b95
```

## Largest distributed run

The distributed path was verified end-to-end with two Erlang nodes (one server
and one silent worker) on one physical laptop. The server was configured with
zero local workers for this test, proving that the returned coin was mined by
the remote node and printed only by the server. The largest number of physical
machines tested was **1**.

## Testing and packaging

Run the built-in SHA-256, argument-parsing, and leading-zero tests:

```sh
make test
```

Create the submission archive:

```sh
make package
```

This produces `project1.zip` containing the executable, README, and Makefile.
