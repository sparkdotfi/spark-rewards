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

    function setUp() public virtual {
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

contract RewardsClaimTestBase is RewardsTestBase {

    IERC20 public token1;
    IERC20 public token2;

    uint256 public valuesLength; // Size of merkle values array of file 1

    string filePath1 = "test/data/exampleTree1.json"; // change this to the path of the file
    string filePath2 = "test/data/exampleTree2.json";

    address wallet = makeAddr("wallet");

    struct Leaf {
        uint256 epoch;
        address account;
        address token;
        uint256 cumulativeAmount;
        bytes32[] proof;
    }

    function setUp() public override {
        token1 = new Token("Test1", "TST1", 1_000_000_000e18);
        token2 = new Token("Test2", "TST2", 1_000_000_000e18);

        super.setUp();

        vm.prank(walletAdmin);
        distributor.setWallet(address(wallet));

        token1.transfer(address(wallet), 1_000_000_000e18);
        token2.transfer(address(wallet), 1_000_000_000e18);

        vm.startPrank(wallet);
        token1.approve(address(distributor), 1_000_000_000e18);
        token2.approve(address(distributor), 1_000_000_000e18);
        vm.stopPrank();

        string memory json = vm.readFile(filePath1);

        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(parseMerkleRoot(json));

        valuesLength = getValuesLength(json);
    }

    function getClaimParams(uint256 index, string memory filePath)
        internal returns (bytes32 root, Leaf memory leaf)
    {
        string memory json = vm.readFile(filePath);

        root = parseMerkleRoot(json);
        leaf = parseLeaf(index, json);
    }

    function getValuesLength(string memory json) public pure returns (uint256) {
        // Parse the totalClaims directly from the JSON file
        return vm.parseJsonUint(json, ".totalClaims") - 1;
    }

    function parseLeaf(uint256 index, string memory json) public pure returns (Leaf memory) {
        // Use the index parameter to dynamically access the values
        string memory indexPath = string(abi.encodePacked(".values[", vm.toString(index), "]"));

        uint256 cumulativeAmount = uint256(vm.parseJsonUint(json, string(abi.encodePacked(indexPath, ".cumulativeAmount"))));
        uint256 epoch            = uint256(vm.parseJsonUint(json, string(abi.encodePacked(indexPath, ".epoch"))));

        address account = vm.parseJsonAddress(json, string(abi.encodePacked(indexPath, ".account")));
        address token   = vm.parseJsonAddress(json, string(abi.encodePacked(indexPath, ".token")));

        // Parse the proof
        bytes32[] memory proof = abi.decode(
            vm.parseJson(json, string(abi.encodePacked(indexPath, ".proof"))),
            (bytes32[])
        );

        return Leaf(epoch, account, token, cumulativeAmount, proof);
    }

    function parseMerkleRoot(string memory json) public pure returns (bytes32) {
        return vm.parseJsonBytes32(json, ".root");
    }

}

contract RewardsClaimFailureTests is RewardsClaimTestBase {

    function test_claim_accountNotMsgSender() public {
        vm.expectRevert("Rewards/invalid-account");
        distributor.claim(1, makeAddr("account"), address(token1), 1, bytes32(0), new bytes32[](0));
    }

    function test_claim_merkleRootNotExpected() public {
        bytes32 root1 = "root1";
        bytes32 root2 = "root2";

        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(root1);

        vm.expectRevert("Rewards/merkle-root-was-updated");
        distributor.claim(1, address(this), address(token1), 1, root2, new bytes32[](0));
    }

    function test_claim_epochClosed() public {
        vm.prank(epochAdmin);
        distributor.setEpochClosed(1, true);

        vm.expectRevert("Rewards/epoch-not-enabled");
        distributor.claim(1, address(this), address(token1), 1, bytes32(0), new bytes32[](0));
    }

    function testFuzz_claim_invalidEpoch(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        ( bytes32 root, Leaf memory leaf ) = getClaimParams(0, filePath1);

        leaf.epoch += 1;

        vm.prank(leaf.account);
        vm.expectRevert("Rewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testFuzz_claim_invalidAccount(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        ( bytes32 root, Leaf memory leaf ) = getClaimParams(0, filePath1);

        leaf.account = makeAddr("fakeAccount");

        vm.prank(leaf.account);
        vm.expectRevert("Rewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testFuzz_claim_invalidToken(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        ( bytes32 root, Leaf memory leaf ) = getClaimParams(0, filePath1);

        leaf.token = makeAddr("fakeToken");

        vm.prank(leaf.account);
        vm.expectRevert("Rewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testFuzz_claim_invalidCumulativeAmount(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        ( bytes32 root, Leaf memory leaf ) = getClaimParams(0, filePath1);

        leaf.cumulativeAmount += 1;

        vm.prank(leaf.account);
        vm.expectRevert("Rewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function test_claim_nothingToClaim(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        ( bytes32 root, Leaf memory leaf ) = getClaimParams(0, filePath1);

        vm.prank(leaf.account);
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);

        vm.prank(leaf.account);
        vm.expectRevert("Rewards/nothing-to-claim");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

}

contract RewardsClaimSuccessTests is RewardsClaimTestBase {

    function test_claim_singleClaim() public {
        uint256 index = 0;

        ( bytes32 root, Leaf memory leaf ) = getClaimParams(index, filePath1);

        IERC20 token = IERC20(leaf.token);

        assertEq(token.balanceOf(wallet),       1_000_000_000e18);
        assertEq(token.balanceOf(leaf.account), 0);

        assertEq(distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch), 0);

        vm.prank(leaf.account);
        uint256 claimedAmount = distributor.claim(
            leaf.epoch,
            leaf.account,
            leaf.token,
            leaf.cumulativeAmount,
            root,
            leaf.proof
        );

        assertEq(claimedAmount, leaf.cumulativeAmount);
        assertEq(claimedAmount, 1000e18);

        assertEq(token.balanceOf(wallet),       1_000_000_000e18 - 1000e18);
        assertEq(token.balanceOf(leaf.account), 1000e18);

        assertEq(distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch), 1000e18);
    }

    function testFuzz_claim_singleClaim(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        ( bytes32 root, Leaf memory leaf ) = getClaimParams(index, filePath1);

        IERC20 token = IERC20(leaf.token);

        assertEq(token.balanceOf(wallet),       1_000_000_000e18);
        assertEq(token.balanceOf(leaf.account), 0);

        assertEq(distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch), 0);

        vm.prank(leaf.account);
        uint256 claimedAmount = distributor.claim(
            leaf.epoch,
            leaf.account,
            leaf.token,
            leaf.cumulativeAmount,
            root,
            leaf.proof
        );

        assertEq(claimedAmount, leaf.cumulativeAmount);

        assertEq(token.balanceOf(wallet),       1_000_000_000e18 - claimedAmount);
        assertEq(token.balanceOf(leaf.account), claimedAmount);

        assertEq(distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch), claimedAmount);
    }

}
