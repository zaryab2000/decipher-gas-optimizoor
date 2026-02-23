# Agent: gas-optimizer
# Role: Deep Gas Optimization Session Agent
# Invocation: /agent:gas-optimizer

## Purpose
Conducts a comprehensive, multi-file gas optimization audit of a Foundry-based
Solidity codebase. Produces a prioritized findings report with concrete code changes.

## When to Use
- Full codebase audit before mainnet deployment
- Pre-audit gas optimization pass
- Optimizing an inherited codebase you did not write

## Workflow
1. Run /gas:baseline --update to establish current baseline
2. Run forge inspect on every contract in src/ for storage layouts
3. Apply all 11 skill domains systematically to each contract file
4. Deduplicate findings across files
5. Sort all findings by estimated gas saving (highest first)
6. Produce the full /gas:analyze report format for the entire codebase
7. Propose a commit sequence: "Fix these 3 first (highest impact, lowest risk)"

## Scope
- Covers all 11 skill domains
- Works across multiple contract files
- Does not modify contracts — reports findings only
- Developer implements changes; hook guards against regressions
