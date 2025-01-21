// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.21;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract Rewards is Ownable {
    using SafeERC20 for IERC20;

    address public immutable token; //TODO make contract support multiple tokens as part of merkle tree
    bytes32 public merkleRoot;

    mapping(address => uint256) public cumulativeClaimed;

    // This event is triggered whenever a call to #setMerkleRoot succeeds.
    event MerkelRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot);
    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(address indexed account, uint256 amount);

    constructor(address owner, address token_) Ownable(owner) {
        token = token_;
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        emit MerkelRootUpdated(merkleRoot, merkleRoot_);
        merkleRoot = merkleRoot_;
    }

    //TODO: add token param to the claim function - token must also be added to the merkle tree
    function claim(
        uint256 index,
        address account,
        uint256 cumulativeAmount,
        bytes32 expectedMerkleRoot,
        bytes32[] calldata merkleProof
    ) external {
        require(merkleRoot == expectedMerkleRoot, "Rewards/merkle-root-was-updated");
        // Verify the merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(index, account, cumulativeAmount));
        require(MerkleProof.verify(merkleProof, expectedMerkleRoot, leaf), "Rewards/invalid-proof");
        // Mark it claimed
        uint256 preclaimed = cumulativeClaimed[account];
        require(preclaimed < cumulativeAmount, "Rewards/nothing-to-claim");
        cumulativeClaimed[account] = cumulativeAmount;

        // Send the token
        unchecked {
            uint256 amount = cumulativeAmount - preclaimed;
            IERC20(token).safeTransfer(account, amount); // TODO pull token from a multisig
            emit Claimed(account, amount);
        }
    }
}