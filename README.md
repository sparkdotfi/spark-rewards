# Spark Rewards

<!-- ![Foundry CI](https://github.com/{org}/{repo}/actions/workflows/ci.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/{org}/{repo}/blob/master/LICENSE) -->

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

Smart contracts that facilitate distribution of rewards.

## Usage

```bash
forge build
```

## Test

```bash
forge test
```

## Generate Merkle Tree Script

This script generates a Merkle Tree from a rewards JSON file and outputs the tree structure, proofs, and root to a specified folder.

### Prerequisites

1. **Install Node.js**: Ensure Node.js is installed. Download it from [Node.js](https://nodejs.org/).
2. **Install Dependencies**:
   ```bash
   npm install
    ```
3. **Run the Script**: 
   ```bash
   cd merkle-tree-scripts
   node generateMerkleTree.js <inputFilePath> <outputFilePath>
   ```
   - Example:
        ```bash
        node generateMerkleTree.js input/example1.json output/merkleTree.json
        ```

***
*The IP in this repository was assigned to Mars SPC Limited in respect of the MarsOne SP*