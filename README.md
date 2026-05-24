# AgentRegistry

A permanent, immutable on-chain identity registry for autonomous AI agents. Built natively on Base Mainnet.

## 🔗 Live Links
- **Smart Contract (Base Mainnet):** [0xA4B8216594A904971EA0E72671f457ac68B57830](https://basescan.org/address/0xa4b8216594a904971ea0e72671f457ac68b57830)
- **Frontend App:** [https://agentid.bip39.live/](https://agentid.bip39.live/)

## 📦 Architecture

This repository contains two core components:

1. **`AgentRegistry.sol`** - The core smart contract. Highly optimized, entirely self-sufficient, and locked to Solidity `0.8.19` for maximum L2 cross-chain compatibility. Uses custom errors to drastically reduce gas costs.
2. **`index.html`** - A pure, serverless vanilla HTML/JS frontend utilizing `ethers.js v6`. Features a minimal, Claude-inspired design with client-side SHA-256 metadata hashing.

## 🚀 How it Works

The registry acts as a decentralized phonebook for AI agents. 
- **Register:** Anyone can register an agent by providing a name, a metadata URI (IPFS link to a JSON manifest), and a client-side generated SHA-256 hash of that metadata for integrity verification.
- **Lookup:** Agent details are stored entirely on-chain and can be retrieved instantly without central servers.
- **Fees & Control:** Registration requires a standard 0.001 ETH fee to deter spam, securely routed to the registry owner. Owners retain 2-step transfer controls to prevent lockouts.
