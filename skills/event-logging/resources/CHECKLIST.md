# Event Logging Checklist

Run before marking any event-logging review complete.

- [ ] Every `storageArray.push()` checked: is the array ever read on-chain? If not → EV-001
- [ ] Replaced storage arrays removed from state declarations (not just the push call)
- [ ] Events defined to capture the same data as the removed push (same fields)
- [ ] Every `event` declaration has `indexed` on address/ID/key fields up to the 3-topic limit (EV-002)
- [ ] `string` and `bytes` fields are NOT indexed
- [ ] `forge test -vvvv` confirms LOG opcode in traces (not SSTORE) after EV-001 changes
