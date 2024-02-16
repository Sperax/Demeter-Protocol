# Contribution Guidelines

Welcome to the Demeter Protocol's repository! We're thrilled that you're interested in contributing to our project. This document provides an overview of how you can get involved and make contributions. Please take a moment to read and understand these guidelines before you start contributing.

## Table of Contents

- [Getting Started](#getting-started)
- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Pull Request Process](#pull-request-process)
- [Community](#community)
- [License](#license)

## Getting Started

Before you start contributing, make sure you have:

- A GitHub account. If you don't have one, you can [sign up here](https://github.com/join).
- Familiarity with Demeter Protocol. You can learn more by visiting our [website](https://www.demeter.sperax.io/) or checking out our [documentation](https://docs.sperax.io/demeter-protocol).
- Foundry. You can follow the steps mentioned [here](https://book.getfoundry.sh/getting-started/installation) to install foundry.

## Code of Conduct

As contributors of this project, we pledge to respect all people who contribute through reporting issues, posting feature requests, updating documentation, submitting pull requests or patches, adding new protocols and other activities.

Project maintainers have the right and responsibility to remove, edit, or reject comments, commits, code, wiki edits, issues, and other contributions that are not aligned to this Code of Conduct.

## How to Contribute

Currently, Demeter protocol is only open for adding new protocols to our growing list of protocols which offers incentivized liquidity pools.

If you want to get in touch with the maintainers for any doubt or question, you can drop a message in `#engineering-dev` room in our official [Discord](https://discord.com/invite/cFdcvj9jMm).

## Development Workflow

To set up a development environment for Demeter Protocol, follow these steps:

1. Fork the [Demeter-Protocol](https://github.com/Sperax/Demeter-Protocol) GitHub repository to your own GitHub account.

1. Clone your forked repository to your local machine:

   ```bash
   git clone https://github.com/your-username/Demeter-Protocol.git
   ```

1. Install the necessary dependencies:

   ```bash
   cd Demeter-Protocol
   forge install
   npm install
   ```

1. Create a new branch for your work:

   ```bash
   git checkout -b wip/protocol-name
   ```

1. Add a new folder under contracts for contracts and protocol's interface

   ```bash
   mkdir contracts/protocol-name
   mkdir contracts/protocol-name/interfaces
   ```

1. Add the smart contracts:

   ```bash
   touch contracts/protocol-name/ProtocolNameFarm.sol
   touch contracts/protocol-name/ProtocolNameFarm_Deployer.sol
   ```

1. Your Farm and FarmDeployer must extend Farm.sol and FarmDeployer.sol under `contracts`.

1. If the desired protocol is a fork of Uniswap V2/ returns ERC20 LP positions, you must follow the steps under `contracts/e20-farms`.

1. Add the logic you would like to add for deposits and withdrawals over Farm and then call the internal functions of Farm for consistency.

1. Farm deployers must collect fees, validate pool while creating a farm and must register the farm in the official FarmFactory contract. Feel free to add/ remove any variables which are needed as per different protocols.

1. Write extensive tests in foundry under tests/protocol-name/ directory as:

   ```bash
   tests/protocol-name/ProtocolNameFarm.t.sol
   tests/protocol-name/ProtocolNameFarm_Deployer.t.sol
   ```

1. Push your changes to your forked repository:

   ```bash
   git push origin wip/protocol-name
   ```

1. Open a pull request on the original repository with a clear description of your changes. Our team will review your pull request and provide feedback.

## Pull Request Process

Please follow these guidelines when submitting a pull request:

1. Keep your pull request focused on a single protocol.

1. Provide a clear and descriptive title for your pull request.

1. Include detailed information in the pull request's description, network, important smart contract addresses, documentation of the protocol you intend to add and the changes you have made in a readme.md file.

1. Add extensive code documentation as per Solidity [standards](https://docs.soliditylang.org/en/latest/natspec-format.html)

1. Ensure all tests pass successfully.

1. Be responsive to feedback and be prepared to make changes to your code if requested.

## Community

Join our community to stay updated and interact with other contributors and users:

- [Website](https://www.sperax.io/)
- [Telegram](https://t.me/SperaxUSD)
- [Discord](https://discord.com/invite/cFdcvj9jMm)
- [Twitter](https://twitter.com/SperaxUSD)
- [Medium](https://medium.com/sperax)

## License

By contributing to our protocol, you agree that your contributions will be licensed under the [MIT LICENSE](https://opensource.org/license/mit/) associated with the project.

Thank you for your interest in Demeter Protocol. We look forward to your contributions and appreciate your support in making our project even better!
