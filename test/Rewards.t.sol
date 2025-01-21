// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import {Rewards} from "../src/Rewards.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

contract RewardsTest is Test {

    Rewards public distributor;
    IERC20 public token;
    address public claimer;

    function setUp() public {
        token = new Token("Test", "TST", 1_000_000 * 1e18);
        distributor = new Rewards(address(this), address(token));
        token.transfer(address(distributor), 1_000_000 * 1e18);
    }
    function testSetMerkleRoot(string memory seed) public {
        bytes32 newRoot = keccak256(abi.encodePacked(seed));
        distributor.setMerkleRoot(newRoot);
        assertEq(distributor.merkleRoot(), newRoot);
    }

    function testClaim() public {
        address account = 0x05fc93DeFFFe436822100E795F376228470FB514;
        uint256 cumulativeAmount = 1000; // First claim 1000 tokens

        bytes32 root = 0x2dae32f7aa8182d9775b5cd13f6b393401158e5bdcdeefaf0b5d22b485887562;
        distributor.setMerkleRoot(root);

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x707e172edca3c0d11e8e9d1622319b2c6e3c57f4d683c7256652a46106ace4f6;
        proof[1] = 0xdcfd854349190e193a15417dc242053133cd95cbe1f893faac582f441529d81b;
        proof[2] = 0x0f792cfa427891b27d8d125181aed22a78b49cdb5cef6f24f3bd1f7dccca6ead;
        proof[3] = 0x251b6161e3ea1e4abccf0219638c1edf425cc848cff2b3471bbb57f184c2068e;

        distributor.claim(0, account, cumulativeAmount, root, proof);
        assertEq(distributor.cumulativeClaimed(account), token.balanceOf(account));

        bytes32 newRoot = 0x79a7519fc31f8f975fcdb38f9e1c4ead9c3da6db369dcb3d51f32270f088a37b;
        distributor.setMerkleRoot(newRoot);
        cumulativeAmount = 1150; // Second claim 1150-1000=150 tokens
        distributor.claim(0, account, cumulativeAmount, newRoot, proof);
        assertEq(distributor.cumulativeClaimed(account), token.balanceOf(account));
    }
}
