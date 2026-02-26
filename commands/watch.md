# /decipher-gas-optimizoor:watch

Toggle real-time gas annotation mode. When active, Claude appends a gas impact note
after every Solidity edit it makes in the current session.

## Activation

When the user runs `/decipher-gas-optimizoor:watch` (with no `--off` flag), output exactly:

```
Gas Watch Mode: ACTIVE — I will annotate every Solidity edit with a gas impact note.
```

No other output. No confirmation questions. Mode is immediately active.

## Behavior while active

After every message in which Claude writes, edits, or rewrites Solidity code, append
this annotation block at the end of the response — after describing the change but
before any follow-up questions:

```
---
Gas note: [what changed and why it affects gas]
Estimated: [+/-X gas] per call to [function name or "all callers"]
```

Rules for the annotation:

- Be specific: name the opcode or pattern (SLOAD, SSTORE, calldata vs memory,
  unchecked, custom error, etc.).
- Include a numeric estimate. Use ranges when the exact saving depends on input size
  or call frequency (e.g., "~97 gas/warm SLOAD avoided × N iterations").
- If the change has no gas impact (e.g., a comment change or NatSpec addition), write:
  ```
  Gas note: No gas impact — comment/NatSpec only.
  ```
- If the change introduces a gas regression, flag it clearly:
  ```
  Gas note: REGRESSION — [what got worse and why]
  Estimated: +X gas per call to [function name]
  ```
- One annotation block per response, even if multiple files were edited. Summarize all
  edits in a single note; list separate line items if edits affect different functions.

## Example annotation

```
Gas note: Replaced `require(msg.sender == owner, "Not owner")` with custom error
`NotOwner()` — eliminates ABI-encoded string revert data (4 bytes selector vs ~96 bytes
`Error(string)` encoding) and reduces deployment bytecode by ~200 bytes.
Estimated: -20 gas per call to setOwner() on the revert path; -~40,000 gas deployment.
```

## Deactivation

When the user runs `/decipher-gas-optimizoor:watch --off`, output exactly:

```
Gas Watch Mode: DEACTIVATED
```

Stop appending annotations for the remainder of the session. Mode deactivates
immediately; the response containing the deactivation message itself does not include
an annotation.

## Notes

- Watch mode is session-scoped. It does not persist across Claude Code restarts.
- Watch mode applies to Claude's own edits, not to code the user pastes or types.
- Watch mode does not run forge or any external tool — annotations are static analysis
  based on the code change, not measured gas from a test run.
- If forge measurement is needed, suggest running `/decipher-gas-optimizoor:analyze` or `/decipher-gas-optimizoor:compare`.
