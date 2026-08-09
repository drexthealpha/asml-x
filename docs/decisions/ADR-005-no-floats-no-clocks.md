# ADR-005: integer micro-units, time as an argument

Date 9 Aug 2026. Status ACCEPTED.

## Decision
The risk engine and all shared value types use integer micro-units (1e6 scale) and
never read a clock. Time is passed in. float_arithmetic is denied at the workspace
lint level and unsafe_code is forbidden.

## Why
Two reasons, both about provability. Floats make invariants unprovable and
introduce rounding an adversary can steer. A function that reads a clock cannot be
symbolically executed or exhaustively tested. Phase 3 formal verification depends
on both properties holding from the start, and retrofitting them later would mean
rewriting the engine.

## Cost
All arithmetic must scale carefully. The micro-squared divisor in notional lives in
exactly one place (OrderIntent::notional_micro) because that is the classic
fixed-point bug. A mutation test covers it.
