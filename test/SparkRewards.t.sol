// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 }  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { SparkRewards } from "../src/SparkRewards.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

contract SparkRewardsTestBase is Test {

    SparkRewards public distributor;

    address admin           = makeAddr("admin");
    address epochAdmin      = makeAddr("epochAdmin");
    address merkleRootAdmin = makeAddr("merkleRootAdmin");
    address walletAdmin     = makeAddr("walletAdmin");

    bytes32 public constant EPOCH_ROLE       = keccak256("EPOCH_ROLE");
    bytes32 public constant MERKLE_ROOT_ROLE = keccak256("MERKLE_ROOT_ROLE");
    bytes32 public constant WALLET_ROLE      = keccak256("WALLET_ROLE");

    function setUp() public virtual {
        distributor = new SparkRewards(admin);
        vm.startPrank(admin);
        distributor.grantRole(EPOCH_ROLE,       epochAdmin);
        distributor.grantRole(MERKLE_ROOT_ROLE, merkleRootAdmin);
        distributor.grantRole(WALLET_ROLE,      walletAdmin);
        vm.stopPrank();
    }

}

contract SparkRewardsAdminFailureTests is SparkRewardsTestBase {

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

contract SparkRewardsAdminSuccessTests is SparkRewardsTestBase {

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

contract SparkRewardsClaimTestBase is SparkRewardsTestBase {

    IERC20 public token1;
    IERC20 public token2;

    uint256 public valuesLength; // Size of merkle values array of file 1

    // NOTE: Complex trees are dynamic and can be replaced in tests, simple cannot
    string filePath1 = "test/data/complexTree1.json";
    string filePath2 = "test/data/complexTree2.json";
    string filePath3 = "test/data/simpleTree1.json";

    address wallet = makeAddr("wallet");

    struct Leaf {
        uint256 epoch;
        address account;
        address token;
        uint256 cumulativeAmount;
        bytes32[] proof;
    }

    function setUp() public virtual override {
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
    }

    function getClaimParams(uint256 index, string memory filePath)
        internal view returns (bytes32 root, Leaf memory leaf)
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

contract SparkRewardsClaimFailureTests is SparkRewardsClaimTestBase {

    bytes32 root;

    function setUp() public override {
        super.setUp();

        string memory json = vm.readFile(filePath1);

        root = parseMerkleRoot(json);

        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(root);
    }

    function test_claim_accountNotMsgSender() public {
        vm.expectRevert("SparkRewards/invalid-account");
        distributor.claim(1, makeAddr("account"), address(token1), 1, root, new bytes32[](0));
    }

    function test_claim_merkleRootNotExpected() public {
        vm.expectRevert("SparkRewards/merkle-root-was-updated");
        distributor.claim(1, address(this), address(token1), 1, "root2", new bytes32[](0));
    }

    function test_claim_epochClosed() public {
        vm.prank(epochAdmin);
        distributor.setEpochClosed(1, true);

        vm.expectRevert("SparkRewards/epoch-not-enabled");
        distributor.claim(1, address(this), address(token1), 1, root, new bytes32[](0));
    }

    function testFuzz_claim_invalidEpoch(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        Leaf memory leaf = parseLeaf(0, vm.readFile(filePath1));

        leaf.epoch += 1;

        vm.prank(leaf.account);
        vm.expectRevert("SparkRewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testFuzz_claim_invalidAccount(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        Leaf memory leaf = parseLeaf(0, vm.readFile(filePath1));

        leaf.account = makeAddr("fakeAccount");

        vm.prank(leaf.account);
        vm.expectRevert("SparkRewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testFuzz_claim_invalidToken(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        Leaf memory leaf = parseLeaf(0, vm.readFile(filePath1));

        leaf.token = makeAddr("fakeToken");

        vm.prank(leaf.account);
        vm.expectRevert("SparkRewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testFuzz_claim_invalidCumulativeAmount(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        Leaf memory leaf = parseLeaf(0, vm.readFile(filePath1));

        leaf.cumulativeAmount += 1;

        vm.prank(leaf.account);
        vm.expectRevert("SparkRewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function test_claim_nothingToClaim(uint256 index) public {
        index = _bound(index, 0, valuesLength);

        Leaf memory leaf = parseLeaf(0, vm.readFile(filePath1));

        vm.prank(leaf.account);
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);

        vm.prank(leaf.account);
        vm.expectRevert("SparkRewards/nothing-to-claim");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

}

contract RewardsClaimFileBasedTests is SparkRewardsClaimTestBase {

    // Using storage to avoid stack too deep error

    // Matches file
    address account1 = 0x1111111111111111111111111111111111111111;
    address account2 = 0x2222222222222222222222222222222222222222;

    string json1;
    string json2;
    string json3;

    uint256 valuesLength1;
    uint256 valuesLength2;
    uint256 valuesLength3;

    bytes32 complexRoot1;
    bytes32 complexRoot2;
    bytes32 simpleRoot;

    function setUp() public override {
        super.setUp();

        json1 = vm.readFile(filePath1);
        json2 = vm.readFile(filePath2);
        json3 = vm.readFile(filePath3);

        valuesLength1 = getValuesLength(json1);
        valuesLength2 = getValuesLength(json2);
        valuesLength3 = getValuesLength(json3);

        complexRoot1 = parseMerkleRoot(json1);
        complexRoot2 = parseMerkleRoot(json2);
        simpleRoot   = parseMerkleRoot(json3);
    }

    function test_claim_singleClaim() public {
        uint256 index = 0;

        ( bytes32 root, Leaf memory leaf ) = getClaimParams(index, filePath3);

        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(simpleRoot);

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
        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(complexRoot1);

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

    function test_claim_e2e_multiUser_multiToken_multiEpoch() public {
        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(simpleRoot); // Reading simple tree

        valuesLength = getValuesLength(json3);
        Leaf[] memory leaves = new Leaf[](8);

        leaves[0] = parseLeaf(0, json3);  // User 1, epoch 1, token1
        leaves[1] = parseLeaf(1, json3);  // User 1, epoch 1, token2
        leaves[2] = parseLeaf(2, json3);  // User 2, epoch 1, token1
        leaves[3] = parseLeaf(3, json3);  // User 2, epoch 1, token2
        leaves[4] = parseLeaf(4, json3);  // User 1, epoch 2, token1
        leaves[5] = parseLeaf(5, json3);  // User 1, epoch 2, token2
        leaves[6] = parseLeaf(6, json3);  // User 2, epoch 2, token1
        leaves[7] = parseLeaf(7, json3);  // User 2, epoch 2, token2

        assertEq(token1.balanceOf(wallet),   1_000_000_000e18);
        assertEq(token1.balanceOf(account1), 0);
        assertEq(token1.balanceOf(account2), 0);

        assertEq(token2.balanceOf(wallet),   1_000_000_000e18);
        assertEq(token2.balanceOf(account1), 0);
        assertEq(token2.balanceOf(account2), 0);

        for (uint256 i; i < 8; ++i) {
            Leaf memory leaf = leaves[i];

            IERC20 token = IERC20(leaf.token);

            uint256 userBalance   = token.balanceOf(leaf.account);
            uint256 walletBalance = token.balanceOf(wallet);

            vm.prank(leaf.account);
            uint256 claimedAmount = distributor.claim(
                leaf.epoch,
                leaf.account,
                leaf.token,
                leaf.cumulativeAmount,
                simpleRoot,
                leaf.proof
            );

            assertEq(claimedAmount, leaf.cumulativeAmount);

            assertEq(token.balanceOf(wallet),       walletBalance - claimedAmount);
            assertEq(token.balanceOf(leaf.account), userBalance   + claimedAmount);

            assertEq(distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch), claimedAmount);
        }

        uint256 sumToken1 = leaves[0].cumulativeAmount + leaves[2].cumulativeAmount + leaves[4].cumulativeAmount + leaves[6].cumulativeAmount;
        uint256 sumToken2 = leaves[1].cumulativeAmount + leaves[3].cumulativeAmount + leaves[5].cumulativeAmount + leaves[7].cumulativeAmount;

        assertEq(token1.balanceOf(wallet),   1_000_000_000e18 - sumToken1);
        assertEq(token1.balanceOf(account1), leaves[0].cumulativeAmount + leaves[4].cumulativeAmount);
        assertEq(token1.balanceOf(account2), leaves[2].cumulativeAmount + leaves[6].cumulativeAmount);

        assertEq(token2.balanceOf(wallet),   1_000_000_000e18 - sumToken2);
        assertEq(token2.balanceOf(account1), leaves[1].cumulativeAmount + leaves[5].cumulativeAmount);
        assertEq(token2.balanceOf(account2), leaves[3].cumulativeAmount + leaves[7].cumulativeAmount);

    }

    function test_claim_e2e_allUsers_bothFiles() public {
        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(complexRoot1);

        Leaf[] memory leaves1 = new Leaf[](valuesLength1);
        Leaf[] memory leaves2 = new Leaf[](valuesLength2);

        for (uint256 i; i < valuesLength1; ++i) {
            leaves1[i] = parseLeaf(i, json1);
        }

        for (uint256 i; i < valuesLength2; ++i) {
            leaves2[i] = parseLeaf(i, json2);
        }

        uint256 token1Claimed;
        uint256 token2Claimed;

        // Step 1: Claim from all users with the first file

        for (uint256 i; i < valuesLength1; ++i) {
            Leaf memory leaf = leaves1[i];

            IERC20 token = IERC20(leaf.token);

            uint256 userBalance   = token.balanceOf(leaf.account);
            uint256 walletBalance = token.balanceOf(wallet);

            vm.prank(leaf.account);
            uint256 claimedAmount = distributor.claim(
                leaf.epoch,
                leaf.account,
                leaf.token,
                leaf.cumulativeAmount,
                complexRoot1,
                leaf.proof
            );

            if      (leaf.token == address(token1)) token1Claimed += claimedAmount;
            else if (leaf.token == address(token2)) token2Claimed += claimedAmount;

            assertEq(claimedAmount, leaf.cumulativeAmount);

            assertEq(token.balanceOf(wallet),       walletBalance - claimedAmount);
            assertEq(token.balanceOf(leaf.account), userBalance   + claimedAmount);

            assertEq(distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch), claimedAmount);
        }

        assertEq(token1.balanceOf(wallet), 1_000_000_000e18 - token1Claimed);
        assertEq(token2.balanceOf(wallet), 1_000_000_000e18 - token2Claimed);

        // Step 2: Demonstrate claims can't happen until root is updated

        Leaf memory failingLeaf = leaves2[0];
        vm.prank(failingLeaf.account);
        vm.expectRevert("SparkRewards/merkle-root-was-updated");
        distributor.claim(
            failingLeaf.epoch,
            failingLeaf.account,
            failingLeaf.token,
            failingLeaf.cumulativeAmount,
            complexRoot2,
            failingLeaf.proof
        );

        // Step 3: Update merkle root

        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(complexRoot2);

        // Step 4: Claim from all users with the second file

        for (uint256 i; i < valuesLength2; ++i) {
            Leaf memory leaf = leaves2[i];

            IERC20 token = IERC20(leaf.token);

            uint256 userBalance       = token.balanceOf(leaf.account);
            uint256 walletBalance     = token.balanceOf(wallet);
            uint256 cumulativeClaimed = distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch);

            vm.prank(leaf.account);
            uint256 claimedAmount = distributor.claim(
                leaf.epoch,
                leaf.account,
                leaf.token,
                leaf.cumulativeAmount,
                complexRoot2,
                leaf.proof
            );

            if      (leaf.token == address(token1)) token1Claimed += claimedAmount;
            else if (leaf.token == address(token2)) token2Claimed += claimedAmount;

            // User gets the difference between the two files for this token and epoch
            assertEq(claimedAmount, leaf.cumulativeAmount - cumulativeClaimed);

            assertEq(token.balanceOf(wallet),       walletBalance - claimedAmount);
            assertEq(token.balanceOf(leaf.account), userBalance   + claimedAmount);

            // After claim state is set to the value in the latest file
            assertEq(distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch), leaf.cumulativeAmount);
        }

        // Same assertions used because it was cumulated in the second loop
        assertEq(token1.balanceOf(wallet), 1_000_000_000e18 - token1Claimed);
        assertEq(token2.balanceOf(wallet), 1_000_000_000e18 - token2Claimed);
    }

    function test_claim_e2e_someUsers_bothFiles() public {
        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(complexRoot1);

        Leaf[] memory leaves1 = new Leaf[](valuesLength1 - 3);  // Remove some claims
        Leaf[] memory leaves2 = new Leaf[](valuesLength2 - 3);  // Remove some claims

        // Remove some claims from beginning of file
        for (uint256 i; i < valuesLength1 - 3; ++i) {
            leaves1[i] = parseLeaf(i + 3, json1);
        }

        // Remove some claims from end of file
        for (uint256 i; i < valuesLength2 - 3; ++i) {
            leaves2[i] = parseLeaf(i, json2);
        }

        uint256 token1Claimed;
        uint256 token2Claimed;

        // Step 1: Claim from most users with the first file (some users don't claim but claim in second file)

        for (uint256 i; i < valuesLength1 - 3; ++i) {
            Leaf memory leaf = leaves1[i];

            IERC20 token = IERC20(leaf.token);

            uint256 userBalance   = token.balanceOf(leaf.account);
            uint256 walletBalance = token.balanceOf(wallet);

            vm.prank(leaf.account);
            uint256 claimedAmount = distributor.claim(
                leaf.epoch,
                leaf.account,
                leaf.token,
                leaf.cumulativeAmount,
                complexRoot1,
                leaf.proof
            );

            if      (leaf.token == address(token1)) token1Claimed += claimedAmount;
            else if (leaf.token == address(token2)) token2Claimed += claimedAmount;

            assertEq(claimedAmount, leaf.cumulativeAmount);

            assertEq(token.balanceOf(wallet),       walletBalance - claimedAmount);
            assertEq(token.balanceOf(leaf.account), userBalance   + claimedAmount);

            assertEq(distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch), claimedAmount);
        }

        assertEq(token1.balanceOf(wallet), 1_000_000_000e18 - token1Claimed);
        assertEq(token2.balanceOf(wallet), 1_000_000_000e18 - token2Claimed);

        // Step 2: Demonstrate claims can't happen until root is updated

        Leaf memory failingLeaf = leaves2[0];
        vm.prank(failingLeaf.account);
        vm.expectRevert("SparkRewards/merkle-root-was-updated");
        distributor.claim(
            failingLeaf.epoch,
            failingLeaf.account,
            failingLeaf.token,
            failingLeaf.cumulativeAmount,
            complexRoot2,
            failingLeaf.proof
        );

        // Step 3: Update merkle root

        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(complexRoot2);

        // Step 4: Claim from most users with the second file (some users don't claim that claimed in first file)

        for (uint256 i; i < valuesLength2 - 3; ++i) {
            Leaf memory leaf = leaves2[i];

            IERC20 token = IERC20(leaf.token);

            uint256 userBalance       = token.balanceOf(leaf.account);
            uint256 walletBalance     = token.balanceOf(wallet);
            uint256 cumulativeClaimed = distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch);

            vm.prank(leaf.account);
            uint256 claimedAmount = distributor.claim(
                leaf.epoch,
                leaf.account,
                leaf.token,
                leaf.cumulativeAmount,
                complexRoot2,
                leaf.proof
            );

            if      (leaf.token == address(token1)) token1Claimed += claimedAmount;
            else if (leaf.token == address(token2)) token2Claimed += claimedAmount;

            // User gets the difference between the two files for this token and epoch
            assertEq(claimedAmount, leaf.cumulativeAmount - cumulativeClaimed);

            assertEq(token.balanceOf(wallet),       walletBalance - claimedAmount);
            assertEq(token.balanceOf(leaf.account), userBalance   + claimedAmount);

            // After claim state is set to the value in the latest file
            assertEq(distributor.cumulativeClaimed(leaf.account, leaf.token, leaf.epoch), leaf.cumulativeAmount);
        }

        // Same assertions used because it was cumulated in the second loop
        assertEq(token1.balanceOf(wallet), 1_000_000_000e18 - token1Claimed);
        assertEq(token2.balanceOf(wallet), 1_000_000_000e18 - token2Claimed);
    }

}

contract SparkRewardsClaimHardcodedTests is SparkRewardsClaimTestBase {

    address account = 0x1111111111111111111111111111111111111111;
    address token   = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;  // token1

    bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;

    uint256 epoch            = 1;
    uint256 cumulativeAmount = 1000e18;

    bytes32[] proof;

    function setUp() public override {
        super.setUp();

        proof.push(0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194);
        proof.push(0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008);
        proof.push(0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe);
        proof.push(0xd3e89f852744a1795a80bb9ca20e1fc04b3362c3b32c704697581b2ac0aeee08);

        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(root);
    }

    function test_claim() public {
        assertEq(token1.balanceOf(wallet),  1_000_000_000e18);
        assertEq(token1.balanceOf(account), 0);

        assertEq(distributor.cumulativeClaimed(account, token, epoch), 0);

        vm.prank(account);
        uint256 amount = distributor.claim(epoch, account, token, cumulativeAmount, root, proof);

        assertEq(amount, 1000e18);

        assertEq(token1.balanceOf(wallet),  1_000_000_000e18 - 1000e18);
        assertEq(token1.balanceOf(account), 1000e18);


        assertEq(distributor.cumulativeClaimed(account, token, epoch), 1000e18);
    }

    function test_claim_cumulativeClaiming() public {
        // Do first claim
        vm.prank(account);
        uint256 amount = distributor.claim(epoch, account, token, cumulativeAmount, root, proof);

        assertEq(amount, 1000e18);

        assertEq(token1.balanceOf(wallet),  1_000_000_000e18 - 1000e18);
        assertEq(token1.balanceOf(account), 1000e18);

        assertEq(distributor.cumulativeClaimed(account, token, epoch), 1000e18);

        // Set new root
        root = 0x3ad180d45b269158a2a43cd36b90dec892aeaf3b841eff43869286d542fe0f98;

        // Second claim
        cumulativeAmount = 1500e18; // Second claim 1500 - 1000 = 500 tokens

        proof[0] = 0x33e3c31aee3e738a8d300e6611c4b026403a6e68da3e93056e5168d79639d4b6;
        proof[1] = 0x0b1ae75516e2ca79d7e3c7b4b8025d10e0a2241e8f4245ba15e2c3f2e1946633;
        proof[2] = 0x66e2eab7a691f0a57807aaafa91b616ed48fe85d9b1b97f690c864a883d7ef28;
        proof[3] = 0xf6442853be236c0988a1b18b85479c6d9fac0e1ac92814a7dea8d7db78d3d221;

        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(root);

        vm.prank(account);
        amount = distributor.claim(epoch, account, token, cumulativeAmount, root, proof);

        assertEq(amount, 500e18);

        assertEq(token1.balanceOf(wallet),  1_000_000_000e18 - 1500e18);
        assertEq(token1.balanceOf(account), 1500e18);

        assertEq(distributor.cumulativeClaimed(account, token, epoch), 1500e18);
    }

    // Test for a Merkle Tree of 100k claimers
    function test_claim_largeMerkleTree() public {
        // Overwrite values from storage to avoid warnings
        account = 0xad5315F51d93692f28b0bc4A85bC9F5BdCe7EE9F;
        root    = 0x9dbd722a81f9d6b2bf5b0c086aa518977d2c701fa859e3a69d4568070526e8cf;

        cumulativeAmount = 5_446_866.727330897165615104e18;

        bytes32[] memory bigProof = new bytes32[](17);
        bigProof[0] = 0x8b41ef8cfa3456fd0e74b25c22f5ea75d8f90b87ced173c5c3fa9635490da87d;
        bigProof[1] = 0x86b25f7d851e9d5a580f6be631916284a5d61e8d951420a5a239da06e667db5c;
        bigProof[2] = 0xb429c39db1d9963f005a261d8ae42526096057c541d133d03158e538b40cdc11;
        bigProof[3] = 0x48a80ab542d618913d340de73bfc4437028b6af3c13a57fb9d36384e7a33a217;
        bigProof[4] = 0x68c6ef1ebe6b59512c32713a44a9c49e82205e508c10c2f24e8fe7522c1baa03;
        bigProof[5] = 0x4741d2548f5c8c42a107a9cd82d9e4b669551ae1215dfbf5e7fba5f0140d1c88;
        bigProof[6] = 0xfea965ea9aee0884a5ec3b644ce19f1b6ddf1ac05f89c7b255167ccd51cda6ba;
        bigProof[7] = 0x40bb89ae5e75a9ba47320770f5f654e3942180539e9397b0abb1a9a8951206a6;
        bigProof[8] = 0x6f7af309e43d8fc8a29bc80bd39d60305beec62f8150a81edbb698fbabb27317;
        bigProof[9] = 0xd1c56f8e63c4f6bd7836fd1e1860e58564f7493e1ea4241ecb3c322415cbd0c0;
        bigProof[10] = 0x7818a2f931951ca5d833115b61a05304e86eeb562cd7db9e35c8e36ddaabc301;
        bigProof[11] = 0x16bbca18dfaeb6eb3d4737dac062ce457cf83042329abdf984881d3a6f478c9a;
        bigProof[12] = 0x2f7d2d40a0350f694d2b375b31ad1ab024c9dad42603a5a7c1a9aae0918917c2;
        bigProof[13] = 0xd9cee42c063d1b588e03b38eff870817b65db1e07c4ab387074f9aa7559d52cb;
        bigProof[14] = 0xc5078cf3741834f7f0aca0ee0026d3dc97ae5e50b209d5aecd2fc7a4efed1fc8;
        bigProof[15] = 0x390c26f77a57339604b70ab6c3c99a4b469c08a2e98c12826a562909a7622424;
        bigProof[16] = 0xd4ae2dc050e58cf4c19700ab97ac40059c1cb232de71ba4f48ae2444f246c462;

        vm.prank(merkleRootAdmin);
        distributor.setMerkleRoot(root);

        assertEq(token1.balanceOf(wallet),  1_000_000_000e18);
        assertEq(token1.balanceOf(account), 0);

        assertEq(distributor.cumulativeClaimed(account, token, epoch), 0);

        vm.prank(account);
        uint256 amount = distributor.claim(epoch, account, token, cumulativeAmount, root, bigProof);

        assertEq(amount, cumulativeAmount);

        assertEq(token1.balanceOf(wallet),  1_000_000_000e18 - cumulativeAmount);
        assertEq(token1.balanceOf(account), cumulativeAmount);

        assertEq(distributor.cumulativeClaimed(account, token, epoch), cumulativeAmount);
    }

}
