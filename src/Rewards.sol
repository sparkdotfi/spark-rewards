// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.21;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract Rewards is Ownable {
    using SafeERC20 for IERC20;

    address public wallet;
    bytes32 public merkleRoot;

    mapping(uint256 => bool) public epochClosed;
    mapping(address => mapping(uint256 => uint256)) public cumulativeClaimed; // account => epoch => amount

    // This event is triggered whenever a call to #setWallet succeeds.
    event WalletUpdated(address oldWallet, address newWallet);
    // This event is triggered whenever a call to #setMerkleRoot succeeds.
    event MerkelRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot);
    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(address indexed account, uint256 amount);
    // This event is triggered whenever a call to #incrementEpoch succeeds.
    event EpochUpdated(uint256 oldEpoch, uint256 newEpoch);
    // This event is triggered whenever a call to #setEpochClosed succeeds.
    event EpochIsClosed(uint256 epoch, bool isClosed);

    constructor() Ownable(msg.sender) {}

    /* ========== ADMIN FUNCTIONS ========== */
    function setWallet(address wallet_) public onlyOwner {
        wallet = wallet_;
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        emit MerkelRootUpdated(merkleRoot, merkleRoot_);
        merkleRoot = merkleRoot_;
    }

    function setEpochClosed(uint256 epoch, bool isClosed) public onlyOwner {
        epochClosed[epoch] = isClosed;
        emit EpochIsClosed(epoch, isClosed);
    }

    /* ========== USER FUNCTIONS ========== */
    function claim(
        uint256 epoch,
        address account,
        address token,
        uint256 cumulativeAmount,
        bytes32 expectedMerkleRoot,
        bytes32[] calldata merkleProof
    ) external {
        require(account == msg.sender, "Rewards/invalid-account");
        require(merkleRoot == expectedMerkleRoot, "Rewards/merkle-root-was-updated");
        require(!epochClosed[epoch], "Rewards/epoch-not-enabled");

        // Construct the leaf
        // See https://github.com/OpenZeppelin/merkle-tree?tab=readme-ov-file#validating-a-proof-in-solidity for more info
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(epoch, account, token, cumulativeAmount))));

        // Verify the proof
        require(MerkleProof.verify(merkleProof, expectedMerkleRoot, leaf), "Rewards/invalid-proof");

        // Mark it claimed
        uint256 preClaimed = cumulativeClaimed[account][epoch];
        require(preClaimed < cumulativeAmount, "Rewards/nothing-to-claim");
        cumulativeClaimed[account][epoch] = cumulativeAmount;

        // Send the token
        unchecked {
            uint256 amount = cumulativeAmount - preClaimed;
            IERC20(token).safeTransferFrom(wallet, account, amount);
            emit Claimed(account, amount);
        }
    }
}
