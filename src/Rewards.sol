// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.21;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract Rewards is Ownable {
    using SafeERC20 for IERC20;

    bytes32 public merkleRoot;
    uint256 public epoch;

    mapping(uint256 => bool) epochEnabled;
    mapping(address => mapping(uint256 => uint256)) public cumulativeClaimed; // account => epoch => amount

    // This event is triggered whenever a call to #setMerkleRoot succeeds.
    event MerkelRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot);
    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(address indexed account, uint256 amount);

    event EpochUpdated(uint256 oldEpoch, uint256 newEpoch);

    event EpochEnabled(uint256 epoch_);

    constructor(address owner) Ownable(owner) {
        epoch = 1;
        enableEpoch(epoch);
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        emit MerkelRootUpdated(merkleRoot, merkleRoot_);
        merkleRoot = merkleRoot_;
    }

    function incrementEpoch() public onlyOwner {
        epoch++;
        enableEpoch(epoch);
        emit EpochUpdated(epoch - 1, epoch);
    }

    function enableEpoch(uint256 epoch_) public onlyOwner {
        epochEnabled[epoch_] = true;
        emit EpochEnabled(epoch_);
    }

    function disableEpoch(uint256 epoch_) public onlyOwner {
        epochEnabled[epoch_] = true;
    }

    function claim(
        uint256 epoch_,
        address account,
        address token,
        uint256 cumulativeAmount,
        bytes32 expectedMerkleRoot,
        bytes32[] calldata merkleProof
    ) external {
        require(account == msg.sender, "Rewards/invalid-account");
        require(merkleRoot == expectedMerkleRoot, "Rewards/merkle-root-was-updated");
        require(epochEnabled[epoch_], "Rewards/epoch-not-enabled");

        // Construct the leaf
        // See https://github.com/OpenZeppelin/merkle-tree?tab=readme-ov-file#validating-a-proof-in-solidity for more info
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(epoch_, account, token, cumulativeAmount))));

        // Verify the proof
        require(MerkleProof.verify(merkleProof, expectedMerkleRoot, leaf), "Rewards/invalid-proof");
        
        // Mark it claimed
        uint256 preclaimed = cumulativeClaimed[account][epoch_];
        require(preclaimed < cumulativeAmount, "Rewards/nothing-to-claim");
        cumulativeClaimed[account][epoch_] = cumulativeAmount;

        // Send the token
        unchecked {
            uint256 amount = cumulativeAmount - preclaimed;
            IERC20(token).safeTransfer(account, amount); // TODO pull token from a multisig
            emit Claimed(account, amount);
        }
    }
}