# Spark Rewards

![Foundry CI](https://github.com/marsfoundation/spark-alm-controller/actions/workflows/ci.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/marsfoundation/spark-alm-controller/blob/master/LICENSE)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

The `SparkRewards` smart contract is designed to facilitate the distribution of ERC20 tokens based on a Merkle tree. The contract allows administrators to manage epochs, update Merkle roots, and enable or disable epochs for claims. Users can claim tokens for a specific epoch by providing a valid Merkle proof.

## Usage

```bash
forge build
```

## Test

```bash
forge test
```

## Deploy

```bash
make deploy
```

## Deployments

| Network  | Address                                                                                                                    |
| -------- | ---------------------------------------------------------------------------------------------------------------------------|
| Ethereum | [0xbaf21A27622Db71041Bd336a573DDEdC8eB65122](https://etherscan.io/address/0xbaf21A27622Db71041Bd336a573DDEdC8eB65122#code) |
| Optimism | [0xf94473Bf6EF648638A7b1eEef354fE440721ef41](https://optimistic.etherscan.io/address/0xf94473Bf6EF648638A7b1eEef354fE440721ef41#code) |

## Key Features

### 1. **Merkle Root Validation**
   - The contract uses a Merkle root to verify claims.
   - Claims are validated using Merkle proofs, ensuring only eligible users can claim tokens.

### 2. **Epoch Management**
   - Claims are organized into distinct epochs.
   - Administrators can open or close epochs to manage claim periods.

### 3. **Cumulative Claim Tracking**
   - The Merkle root can be updated, with claims tracked cumulatively for each unique combination of user, token, and epoch.
   - This enables ongoing distributions without users having to claim every single distribution, as rewards accumulate.
      - For example, if this contract is used for weekly rewards, a user doesn't need to claim each week's rewards separately but can choose to claim all accumulated rewards after 4 weeks, reducing transaction costs.

### 4. **External Wallet for Rewards**
   - The contract pulls tokens from a specified wallet for claims.
   - Administrators can set or update the wallet address.

### 5. **Role-Based Controls**
   - The contract implements role-based access control:
     - **EPOCH_ROLE**: Manages epoch status (open/close).
     - **MERKLE_ROOT_ROLE**: Updates the Merkle root.

## Merkle Tree Assumptions
For the spark-rewards cumulative claims to function properly, the Merkle tree is expected to adhere to the following properties:

1. The Merkle tree can contain several epochs.
2. The Merkle tree's leaves are not removed unless the leaves' epoch is permanently closed.
3. When new rewards for an epoch come in and a user already has a previous leaf for that (epoch, account, token) the Merkle tree updates that leaf with the cumulative amount.
4. The Merkle tree's leaves are unique by (epoch, account, token), i.e., there can't be several leaves (differing in amounts only) for the same account, token, and epoch.

## Functions

### **Admin Functions**
1. `setWallet(address wallet_)`
   - Sets or updates the wallet address from which tokens are pulled for claims.
   - Requires `DEFAULT_ADMIN_ROLE`.
   - Emits a `WalletUpdated` event.

2. `setMerkleRoot(bytes32 merkleRoot_)`
   - Updates the Merkle root for claims verification.
   - Requires `MERKLE_ROOT_ROLE`.
   - Emits a `MerkleRootUpdated` event.

3. `setEpochClosed(uint256 epoch, bool isClosed)`
   - Opens or closes an epoch.
   - Requires `EPOCH_ROLE`.
   - Emits an `EpochIsClosed` event.

### **User Functions**
1. `claim(uint256 epoch, address account, address token, uint256 cumulativeAmount, bytes32 expectedMerkleRoot, bytes32[] calldata merkleProof) returns (uint256 claimedAmount)`
   - Allows users to claim tokens for a specific epoch.
   - Validates the claim using:
     - Epoch number.
     - Current Merkle root.
     - A Merkle proof.
   - Ensures users cannot claim more than their entitled amount.
   - Tokens are transferred from the `wallet` to the claimer's address.
   - Emits a `Claimed` event upon success.

## Events

1. **`WalletUpdated(address oldWallet, address newWallet)`**
   - Emitted when the wallet holding rewards is updated by the admin.

2. **`MerkleRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot)`**
   - Emitted when the Merkle root is updated by the admin.

3. **`EpochIsClosed(uint256 epoch, bool isClosed)`**
   - Emitted when an epoch is opened or closed.

4. **`Claimed(uint256 indexed epoch, address indexed account, address indexed token, uint256 amount)`**
   - Emitted when a user successfully claims tokens.

## Example Claim Workflow

1. **Admin**:
   - Sets the `wallet` address. Requires approval.
   - Updates the Merkle root with eligible claims.
   - Opens or closes epochs as needed.

2. **User**:
   - Retrieves their proof and data from the Merkle tree.
   - Calls `claim` with:
     - Epoch.
     - Their account address.
     - Token address.
     - Cumulative amount.
     - Expected Merkle root.
     - Merkle proof.


## Merkle Tree Script

The `generateMerkleTree.js` script generates a Merkle Tree from a rewards JSON input file and outputs the tree structure, proofs, and root to a specified filepath. You can find example input files in the `merkle-tree-scripts/input/` folder to see the required formatting of the input. To generate randomized input for testing, see the Generate Input Script section below.

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
Example:
   ```bash
   node generateMerkleTree.js input/example1.json output/merkleTree.json
   ```

## Generate Input Script

The `generateInput.js` script is used to generate large input files of randomized and complex data to generate Merkle trees for testing. The generated input file can be used by generateMerkleTree.js script to then generate a complex Merkle tree for testing purposes. You can edit the constants of the `generateInput.js` file to your needs.

### Prerequisites

1. **Install Node.js**: Ensure Node.js is installed. Download it from [Node.js](https://nodejs.org/).
2. **Install Dependencies**:
   ```bash
   npm install
    ```
3. **Run the Script**:
   ```bash
   cd merkle-tree-scripts
   node generateInput.js
   ```

***
*The IP in this repository was assigned to Mars SPC Limited in respect of the MarsOne SP*
<p align="center">
  <img src="https://github.com/user-attachments/assets/841397d0-0cd4-4464-b4b4-6024b6ad6c6d" height="120" />
</p>
