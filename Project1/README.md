# COP5615 Project 1 — Bitcoin Miner

## Group members

- Paresh Devlekar — GatorLink: **TODO**
- Omkar Salkade — GatorLink: **TODO**

## Current implementation (Paresh's portion)

This checkpoint implements local, multi-core mining exclusively with Erlang
actors. A boss actor assigns non-overlapping numeric ranges to one worker actor
per online Erlang scheduler. Workers hash candidate strings with SHA-256 and
send successful coins back to the boss, which is the only process that prints
results.

The distributed server/remote-worker mode, final benchmarking, and completed
results sections are intentionally left for the teammate's portion.

## Run

Erlang/OTP 24 or newer is recommended.

```sh
cd Project1
chmod +x project1.escript
GATORLINK=your_gatorlink ./project1.escript 4
```

Each result is printed as required:

```text
input-string<TAB>lowercase-sha256-hash
```

The program runs until stopped with `Ctrl-C`.

## Work-unit size

The current work unit is **10,000 candidate strings**. This is a provisional
value chosen to amortize actor-message overhead while still redistributing work
frequently. Before final submission, benchmark several sizes (for example 1,000,
5,000, 10,000, and 50,000) on the submission machine and record the measured
best value and methodology here.

## Required final results

### Input 4 output

TODO: Paste representative coins produced with difficulty 4.

### Timing and effective parallelism

TODO: Run with the shell's `time` command and report real, user, and system
times. Explain `(user + system) / real` as the approximate number of cores used.

### Coin with the most leading zeroes

TODO

### Largest distributed run

TODO: Record the largest number of machines/laptops used after distributed mode
is implemented.

## Teammate handoff

The remaining portion should add a distributed mode in which:

1. A numeric argument starts the server/boss and its local workers.
2. An IP-address argument starts a silent remote worker node.
3. Remote workers request work from the server boss.
4. Only the server prints discovered coins.
5. Node naming, cookies, connection failures, and workers joining at any time
   are handled and documented.
