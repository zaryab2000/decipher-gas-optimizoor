# Custom Errors Checklist

Run before marking any custom-errors review complete.

- [ ] Every `require(cond, "string")` replaced with `if (!cond) revert CustomError()` (CE-001)
- [ ] Every `revert("string")` replaced with `revert CustomError()` (CE-002)
- [ ] Custom error declarations are at contract scope, not inside functions
- [ ] Same error reused across multiple call sites when meaning is identical
- [ ] CE-003 applied where runtime values (amounts, addresses) aid debugging
- [ ] Test files exempted — string messages in tests are acceptable for output clarity
- [ ] `forge test` passes — no selector mismatch in test expectations
