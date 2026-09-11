# Gas Sponsorship Protocol v1

**A Solidity-based gas sponsorship system for blockchain applications**

**Author / Licensor:** Mubiru Ibrahim Urufat
**Version:** v1
**Solidity:** `^0.8.35`
**Framework:** Foundry

---

## Overview

Gas Sponsorship Protocol v1 is a smart-contract system designed to allow a sponsor to fund gas payments for eligible blockchain transactions.

The system separates sponsorship funds, sponsor registration, transaction execution, and gas reimbursement into dedicated contracts.

The project was developed with a strong focus on:

* Solidity smart-contract security
* access control
* transaction authorization
* replay protection
* nonce management
* deadline validation
* ETH balance protection
* failed-transfer handling
* fuzz testing
* invariant testing
* integration testing
* security testing
* formal verification

---

## Architecture

The protocol consists of the following main contracts:

### `GasSponsor.sol`

Manages the sponsor's ETH balance.

Responsibilities include:

* receiving sponsor deposits
* managing the authorized router
* releasing approved gas payments
* protecting the sponsor balance
* owner withdrawals
* enforcing sponsorship limits
* managing authorized users

### `SponsorRegistry.sol`

Manages sponsor configuration.

Responsibilities include:

* sponsor registration
* sponsor removal
* gas-sponsor configuration
* router configuration
* sponsor status management

### `GasSponsorRouter.sol`

Handles sponsored meta-transactions.

Responsibilities include:

* signature verification
* EIP-712 typed-data authorization
* nonce validation
* deadline validation
* transaction execution
* gas sponsorship interaction
* protection against unauthorized execution

### `MockTarget.sol`

A testing target used to verify that sponsored transactions can reach another contract while preserving the intended user context.

### `ReentrantTarget.sol`

A security-testing contract used to evaluate reentrancy-related behavior.

---

## Security Testing

Security is a major part of this project.

The repository contains several levels of testing:

### Unit Testing

Individual contract functions are tested for expected behavior, access control, validation, and failure conditions.

### Fuzz Testing

The project uses Foundry fuzz testing to test contracts against many automatically generated inputs.

Fuzz tests cover areas including:

* gas release
* router execution
* sponsor registration
* invalid inputs
* arbitrary users and relayers
* authorization boundaries

### Invariant Testing

Invariant tests verify properties that must remain true across sequences of contract interactions.

Examples include:

* sponsor balance safety
* registration consistency
* authorization properties
* system state integrity

### Integration Testing

Integration tests verify interaction between:

* `GasSponsor`
* `SponsorRegistry`
* `GasSponsorRouter`
* target contracts

### Security Testing

Dedicated security tests examine malicious and abnormal behavior, including unauthorized calls, invalid signatures, replay attempts, and other attack scenarios.

### Formal Verification

Formal verification tests are included using **Halmos** and **Z3**.

The verified properties include:

* only the owner can withdraw
* only the authorized router can release gas
* gas release cannot exceed the sponsor balance
* invalid zero-address relayers are rejected

---

## Security Report

A developer self-audit/security review is included in:

```text
security/GasSponsorship-Security-Audit-v1.md
```

The security report is cryptographically committed to the deployed contract through the immutable:

```solidity
SECURITY_REPORT_HASH
```

This allows the corresponding report version to be verified against the hash stored by the contract.

### Important

This security review is a **developer self-audit**, not an independent third-party audit.

The protocol should receive an independent professional security audit before production deployment involving significant funds.

---

## Current Security Position

Gas Sponsorship v1 has undergone:

* unit testing
* fuzz testing
* invariant testing
* integration testing
* dedicated security testing
* formal verification

However, testing and formal verification do not prove that a smart contract is completely free of vulnerabilities.

Potential users should conduct their own review and obtain an independent audit before using the system with significant funds.

---

## Known v1 Design Limitations

Gas Sponsorship v1 is intentionally treated as a foundation for future development.

Important areas for a future version include stronger sponsor-controlled sponsorship policies, including:

* sponsor-controlled maximum sponsorship amounts
* sponsor-controlled user eligibility
* sponsor-controlled target eligibility
* sponsor-controlled function eligibility
* more sophisticated sponsorship policies
* improved economic controls
* settlement and revenue mechanisms

These features are planned for a future project/version and should not be assumed to exist in v1.

---

## Project Goals

This project demonstrates practical experience with:

* Solidity development
* Foundry
* smart-contract architecture
* Ethereum security
* EIP-712
* cryptographic signatures
* access control
* fuzz testing
* invariant testing
* integration testing
* formal verification
* security analysis
* deployment automation
* blockchain development workflows

The project is also intended as part of the developer portfolio of **Mubiru Ibrahim Urufat**.

---

## Commercial Licensing

Gas Sponsorship Protocol v1 is **not released under an unrestricted open-source commercial license**.

The source code is available for inspection, education, research, security review, and portfolio evaluation.

**Commercial deployment, commercial use, resale, sublicensing, or redistribution requires a separate commercial license from Mubiru Ibrahim Urufat.**

See:

```text
LICENSE
```

for the applicable commercial licensing terms.

Commercial licensing may be negotiated depending on the intended use, deployment requirements, modification rights, redistribution rights, and other commercial requirements.

---

## Contact

For commercial licensing, integration, collaboration, or additional information:

**Mubiru Ibrahim Urufat**

**WhatsApp:** `+256 700603705`

**GitHub:** `mubiruibrahim043-maker`

---

## Repository Structure

```text
Gas-sponsorship/
│
├── .github/
│   └── workflows/
│
├── script/
│   ├── Deploy.s.sol
│   └── Relayer.s.sol
│
├── security/
│   └── GasSponsorship-Security-Audit-v1.md
│
├── src/
│   ├── GasSponsor.sol
│   ├── GasSponsorRouter.sol
│   ├── SponsorRegistry.sol
│   ├── MockTarget.sol
│   └── ReentrantTarget.sol
│
├── test/
│   ├── formal/
│   └── unit test/
│       ├── FuzzTest/
│       ├── Integration/
│       ├── Invariant/
│       └── Security/
│
├── foundry.toml
├── foundry.lock
├── LICENSE
└── README.md
```

---

## Development

Install Foundry and clone the repository.

Build:

```bash
forge build
```

Run the complete test suite:

```bash
forge test
```

Run formatting:

```bash
forge fmt
```

Run formal verification:

```bash
halmos --contract GasSponsorFormal --solver z3
```

---

## Disclaimer

This software is provided for development, research, evaluation, and authorized commercial use under the applicable license.

Smart contracts interact with blockchain networks and may involve irreversible transactions and financial risk.

No guarantee is made that the software is free from vulnerabilities or suitable for a particular purpose.

Users and commercial licensees are responsible for performing appropriate security review, testing, deployment configuration, and risk assessment before using the software with real assets.

---

## License

**Gas Sponsorship Commercial License v1.0**

Copyright © 2026 **Mubiru Ibrahim Urufat**. All rights reserved.

Commercial rights are available under a separate commercial license agreement.

