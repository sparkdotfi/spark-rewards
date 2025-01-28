// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 }  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Rewards } from "../src/Rewards.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

contract RewardsTestBase is Test {

    Rewards public distributor;

    address epochAdmin      = makeAddr("epochAdmin");
    address merkleRootAdmin = makeAddr("merkleRootAdmin");
    address walletAdmin     = makeAddr("walletAdmin");

    bytes32 public constant EPOCH_ROLE       = keccak256("EPOCH_ROLE");
    bytes32 public constant MERKLE_ROOT_ROLE = keccak256("MERKLE_ROOT_ROLE");
    bytes32 public constant WALLET_ROLE      = keccak256("WALLET_ROLE");

    function setUp() public {
        distributor = new Rewards();

        distributor.grantRole(EPOCH_ROLE,       epochAdmin);
        distributor.grantRole(MERKLE_ROOT_ROLE, merkleRootAdmin);
        distributor.grantRole(WALLET_ROLE,      walletAdmin);
    }

}

contract RewardsAdminFailureTests is RewardsTestBase {

    function test_setWallet_notWalletRole() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            WALLET_ROLE
        ));
        distributor.setWallet(makeAddr("newWallet"));
    }

    function test_setMerkleRoot_notMerkleRootRole() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            MERKLE_ROOT_ROLE
        ));
        distributor.setMerkleRoot(bytes32("newRoot"));
    }

    function test_setEpochClosed_notEpochRole() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            EPOCH_ROLE
        ));
        distributor.setEpochClosed(1, true);
    }

}

contract RewardsAdminSuccessTests is RewardsTestBase {

    event EpochIsClosed(uint256 indexed epoch, bool isClosed);
    event MerkleRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot);
    event WalletUpdated(address indexed oldWallet, address indexed newWallet);

    function test_setWallet() public {
        address wallet1 = makeAddr("wallet1");
        address wallet2 = makeAddr("wallet2");

        assertEq(distributor.wallet(), address(0));

        vm.prank(walletAdmin);
        vm.expectEmit(address(distributor));
        emit WalletUpdated(address(0), wallet1);
        distributor.setWallet(wallet1);

        assertEq(distributor.wallet(), wallet1);

        vm.prank(walletAdmin);
        vm.expectEmit(address(distributor));
        emit WalletUpdated(wallet1, wallet2);
        distributor.setWallet(wallet2);

        assertEq(distributor.wallet(), wallet2);
    }

    function test_setMerkleRoot() public {
        bytes32 root1 = "root1";
        bytes32 root2 = "root2";

        assertEq(distributor.merkleRoot(), bytes32(0));

        vm.prank(merkleRootAdmin);
        vm.expectEmit(address(distributor));
        emit MerkleRootUpdated(bytes32(0), root1);
        distributor.setMerkleRoot(root1);

        assertEq(distributor.merkleRoot(), root1);

        vm.prank(merkleRootAdmin);
        vm.expectEmit(address(distributor));
        emit MerkleRootUpdated(root1, root2);
        distributor.setMerkleRoot(root2);

        assertEq(distributor.merkleRoot(), root2);
    }

    function test_setEpochClosed() public {
        assertEq(distributor.epochClosed(1), false);

        vm.prank(epochAdmin);
        vm.expectEmit(address(distributor));
        emit EpochIsClosed(1, true);
        distributor.setEpochClosed(1, true);

        assertEq(distributor.epochClosed(1), true);
    }

}

// contract RewardsTestBase is Test {

//     Rewards public distributor;

//     IERC20 public token1;
//     IERC20 public token2;

//     uint256 public valuesLength; // Size of merkle values array of file 1

//     string filePath1 = "test/data/exampleTree1.json"; // change this to the path of the file
//     string filePath2 = "test/data/exampleTree2.json";

//     address epochAdmin      = makeAddr("epochAdmin");
//     address merkleRootAdmin = makeAddr("merkleRootAdmin");
//     address walletAdmin     = makeAddr("walletAdmin");

//     address wallet = makeAddr("wallet");

//     bytes32 public constant EPOCH_ROLE       = keccak256("EPOCH_ROLE");
//     bytes32 public constant MERKLE_ROOT_ROLE = keccak256("MERKLE_ROOT_ROLE");
//     bytes32 public constant WALLET_ROLE      = keccak256("WALLET_ROLE");

//     struct Leaf {
//         uint256 epoch;
//         address account;
//         address token;
//         uint256 cumulativeAmount;
//         bytes32[] proof;
//     }

//     function setUp() public {
//         token1 = new Token("Test1", "TST1", 1_000_000_000e18);
//         token2 = new Token("Test2", "TST2", 1_000_000_000e18);

//         distributor = new Rewards();

//         distributor.grantRole(EPOCH_ROLE,       epochAdmin);
//         distributor.grantRole(MERKLE_ROOT_ROLE, merkleRootAdmin);
//         distributor.grantRole(WALLET_ROLE,      walletAdmin);

//         vm.prank(walletAdmin);
//         distributor.setWallet(address(wallet));

//         token1.transfer(address(wallet), 1_000_000_000e18);
//         token2.transfer(address(wallet), 1_000_000_000e18);

//         vm.startPrank(wallet);
//         token1.approve(address(distributor), 1_000_000_000e18);
//         token2.approve(address(distributor), 1_000_000_000e18);
//         vm.stopPrank();

//         // // Number of claimers in the test files
//         // valuesLength = getValuesLength(vm.readFile(filePath1));
//     }

// }
