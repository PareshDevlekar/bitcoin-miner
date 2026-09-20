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

The numeric argument is the required number of leading hexadecimal zeroes.
The server also starts one local worker actor per online Erlang scheduler.

```sh
cd Project1
chmod +x project1.escript
GATORLINK=paresh.devlekar ./project1.escript 4
```

The server prints its IPv4 address at startup. It mines continuously until
stopped with `Ctrl-C`.

## Run a remote worker

Copy the `Project1` directory to another machine with Erlang installed, then
pass the server's displayed IPv4 address:

```sh
cd Project1
chmod +x project1.escript
./project1.escript 10.22.13.155
```

The remote process is intentionally silent. It connects to the registered boss,
requests a work unit, mines it, returns any coins, and requests another unit.
If the server is unavailable, it retries every two seconds. All coins are
printed by the server.

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

The selected work unit is **10,000 candidate strings**. We compared 1,000,
10,000, and 50,000 candidates per assignment by mining 100 coins at difficulty
4 with 10 local worker actors. The measured real times were 0.99 s, 0.96 s, and
0.97 s respectively. A unit of 10,000 was the fastest in this test while still
allowing work to be redistributed frequently when machines join.

| Candidates per work unit | Real time |
| ---: | ---: |
| 1,000 | 0.99 s |
| 10,000 | 0.96 s |
| 50,000 | 0.97 s |

## Result for input 4

The following coins were produced with `GATORLINK=paresh.devlekar` and input
`4`:

```text
paresh.devlekar;59548	0000acb76625374ba307f9cafbac9d75e3d93293550e5f8c6b81eb6eea1220ad
paresh.devlekar;176475	0000b09edbfc296bb07273339061d6e15f420d9c74adfea8531a3d25ed34d301
paresh.devlekar;179337	00005e34d3da0d26c53b81f88311688be13ca2e4a98794b5d6ca2920e1bf2149
paresh.devlekar;196515	00007f1ee04a4377b6a5b7667df5aba3a33375bda8db29fad500ab9f6693df77
paresh.devlekar;255977	0000d43c82e72a7875a6b9f899b85607938278b49813afeda325345d20710e58
```

## Running time and parallelism

The 10,000-unit input-4 run used 10 local worker actors and stopped after 100
coins for a repeatable measurement:

```text
real 0.96
user 7.37
sys  0.35
```

The CPU-to-real-time ratio was `(7.37 + 0.35) / 0.96 = 8.04`, showing that
roughly eight CPU cores were used effectively during the run.

For repeatable measurements, `PROJECT1_MAX_COINS` can stop the server after a
specified number of coins. This option is not needed for normal submission use:

```sh
/usr/bin/time -p env PROJECT1_MAX_COINS=100 GATORLINK=paresh.devlekar ./project1.escript 4
```

## Coin with the most leading zeroes

The best coin found during the recorded runs had five leading zeroes:

```text
paresh.devlekar;218955	00000dfd7b4e738b4094c05bb9fe3d412cbc0c9ca22cc80013dacf8e2c01db8f
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
