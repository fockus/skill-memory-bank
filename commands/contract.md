---

## description: Contract-First — define the interface, write contract tests, then implement

allowed-tools: [Read, Glob, Grep, Bash, Write]

# Contract-First: $ARGUMENTS

## 1. Analysis

- Study the existing interfaces and contracts in the project
- Read `./.memory-bank/plan.md` and any ADRs if they exist
- Determine which layers are affected (`handler` / `service` / `repository` / `infra`)

## 2. Define the contract

Show me first:

- The interface (method signatures, input/output types)
- Usage examples (Specification by Example): concrete inputs → expected outputs
- Failure scenarios: what can go wrong → which errors are returned

**Ask for confirmation before continuing.**

## 3. Contract tests

After the contract is approved:

- Write tests for the interface (Testing Trophy: prioritize integration tests)
- Tests must verify the contract, not the implementation
- Tests should fail first (the implementation does not exist yet)
- Run them and make sure they fail for the right reason

## 4. Implementation

- Implement the interface
- Run the contract tests — all must pass
- Contract tests must NOT change during implementation. If you need to change them, the contract was defined incorrectly; go back to step 2

## 5. Finalization

- Run the full test suite
- If Memory Bank is active, add a note in `notes/`