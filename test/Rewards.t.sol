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
    IERC20 public token1; // 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f
    IERC20 public token2; // 0x2e234DAe75C793f67A35089C9d99245E1C58470b
    uint256 public valuesLength; // Size of merkle values array of file 1
    string filePath1 = "test/data/exampleTree1.json"; // change this to the path of the file
    string filePath2 = "test/data/exampleTree2.json";
    address wallet = 0x1234123412341234123412341234123412341234;

    struct Leaf {
        uint256 epoch;
        address account;
        address token;
        uint256 cumulativeAmount;
        bytes32[] proof;
    }

    function setUp() public {
        token1 = new Token("Test1", "TST1", 1_000_000 * 1e18);
        token2 = new Token("Test2", "TST2", 1_000_000 * 1e18);

        distributor = new Rewards(address(this));
        distributor.setWallet(address(wallet));

        token1.transfer(address(wallet), 1_000_000 * 1e18);
        token2.transfer(address(wallet), 1_000_000 * 1e18);

        vm.startPrank(wallet);
        token1.approve(address(distributor), 1_000_000 * 1e18);
        token2.approve(address(distributor), 1_000_000 * 1e18);
        vm.stopPrank();

        string memory json = vm.readFile(filePath1);
        valuesLength = getValuesLength(json); // Number of claimers in the test files
    }

    function parseMerkleRoot(string memory json) public pure returns (bytes32) {
        return vm.parseJsonBytes32(json, ".root");
    }

    function parseLeaf(uint256 index, string memory json) public pure returns (Leaf memory) {
        // Use the index parameter to dynamically access the values
        string memory indexPath = string(abi.encodePacked(".values[", vm.toString(index), "]"));

        uint256 epoch = uint256(vm.parseJsonUint(json, string(abi.encodePacked(indexPath, ".epoch"))));
        address account = vm.parseJsonAddress(json, string(abi.encodePacked(indexPath, ".account")));
        address token = vm.parseJsonAddress(json, string(abi.encodePacked(indexPath, ".token")));
        uint256 cumulativeAmount =
            uint256(vm.parseJsonUint(json, string(abi.encodePacked(indexPath, ".cumulativeAmount"))));

        // Parse the proof
        bytes32[] memory proof =
            abi.decode(vm.parseJson(json, string(abi.encodePacked(indexPath, ".proof"))), (bytes32[]));

        return Leaf(epoch, account, token, cumulativeAmount, proof);
    }

    function getValuesLength(string memory json) public pure returns (uint256) {
        // Parse the totalClaims directly from the JSON file
        return vm.parseJsonUint(json, ".totalClaims") - 1;
    }

    /* ========== ADMIN FUNCTIONS ========== */
    function testSetWallet(address account) public {
        distributor.setWallet(account);
        assertEq(distributor.wallet(), account);
    }

    function testSetWalletOnlyOwner(address account) public {
        vm.assume(account != address(this));
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", account));
        distributor.setWallet(account);
    }

    function testSetEpochClosed(uint256 epoch) public {
        distributor.setEpochClosed(epoch, true);
        assert(distributor.epochClosed(epoch));
    }

    function testSetEpochClosedOnlyOwner(address account, uint256 epoch) public {
        vm.assume(account != address(this));
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", account));
        distributor.setEpochClosed(epoch, true);
    }

    function testSetMerkleRoot(string memory seed) public {
        bytes32 newRoot = keccak256(abi.encodePacked(seed));
        distributor.setMerkleRoot(newRoot);
        assertEq(distributor.merkleRoot(), newRoot);
    }

    function testSetMerkleRootInvalidSender(address account) public {
        vm.assume(account != address(this));
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", account));
        distributor.setMerkleRoot(0);
    }

    /* ========== CLAIM TESTS ========== */
    function testClaimFromFile(uint256 index) public {
        index = bound(index, 0, valuesLength);

        string memory json = vm.readFile(filePath1);
        bytes32 root = parseMerkleRoot(json);
        Leaf memory leaf = parseLeaf(index, json);

        distributor.setMerkleRoot(root);

        vm.prank(leaf.account);
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
        assertEq(distributor.cumulativeClaimed(leaf.account, leaf.epoch), IERC20(leaf.token).balanceOf(leaf.account));
    }

    function testClaimCumulativeFromFile(uint256 index) public {
        // Note both files being imported in this test must keep the same ordering of rewards to work
        index = bound(index, 0, valuesLength);
        string memory json = vm.readFile(filePath1);
        bytes32 root = parseMerkleRoot(json);
        Leaf memory leaf = parseLeaf(index, json);

        distributor.setMerkleRoot(root);

        vm.prank(leaf.account);
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
        assertEq(distributor.cumulativeClaimed(leaf.account, leaf.epoch), IERC20(leaf.token).balanceOf(leaf.account));

        json = vm.readFile(filePath2);
        root = parseMerkleRoot(json);
        leaf = parseLeaf(index, json);

        distributor.setMerkleRoot(root);
        vm.prank(leaf.account);
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
        assertEq(distributor.cumulativeClaimed(leaf.account, leaf.epoch), IERC20(leaf.token).balanceOf(leaf.account));
    }

    function testClaimFailInvalidAccountFromFile(uint256 index, address account) public {
        index = bound(index, 0, valuesLength);

        string memory json = vm.readFile(filePath1);
        bytes32 root = parseMerkleRoot(json);
        Leaf memory leaf = parseLeaf(index, json);
        vm.assume(leaf.account != account);

        distributor.setMerkleRoot(root);

        vm.prank(account);
        vm.expectRevert("Rewards/invalid-account");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testClaimFailInvalidProofFromFile(uint256 index, bytes32 proof) public {
        index = bound(index, 0, valuesLength);

        string memory json = vm.readFile(filePath1);
        bytes32 root = parseMerkleRoot(json);
        Leaf memory leaf = parseLeaf(index, json);
        leaf.proof[0] = proof;

        distributor.setMerkleRoot(root);

        vm.prank(leaf.account);
        vm.expectRevert("Rewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testClaimInvalidRootFromFile(uint256 index, bytes32 newRoot_) public {
        index = bound(index, 0, valuesLength);

        string memory json = vm.readFile(filePath1);
        bytes32 root = parseMerkleRoot(json);
        vm.assume(root != newRoot_);

        Leaf memory leaf = parseLeaf(index, json);

        distributor.setMerkleRoot(newRoot_);

        vm.prank(leaf.account);
        vm.expectRevert("Rewards/merkle-root-was-updated");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testClaimInvalidAmountFromFile(uint256 index, uint256 amount) public {
        vm.assume(amount != 1000000000000000000000);
        index = bound(index, 0, valuesLength);

        string memory json = vm.readFile(filePath1);
        bytes32 root = parseMerkleRoot(json);
        Leaf memory leaf = parseLeaf(index, json);
        leaf.cumulativeAmount = amount;

        distributor.setMerkleRoot(root);

        vm.prank(leaf.account);
        vm.expectRevert("Rewards/invalid-proof");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testClaimInvalidEpochFromFile(uint256 index) public {
        index = bound(index, 0, valuesLength);

        string memory json = vm.readFile(filePath1);
        bytes32 root = parseMerkleRoot(json);
        Leaf memory leaf = parseLeaf(index, json);

        distributor.setMerkleRoot(root);
        distributor.setEpochClosed(leaf.epoch, true);
        vm.prank(leaf.account);
        vm.expectRevert("Rewards/epoch-not-enabled");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    function testNothingToClaimFromFile(uint256 index) public {
        index = bound(index, 0, valuesLength);

        string memory json = vm.readFile(filePath1);
        bytes32 root = parseMerkleRoot(json);
        Leaf memory leaf = parseLeaf(index, json);

        distributor.setMerkleRoot(root);

        vm.startPrank(leaf.account);
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
        assertEq(distributor.cumulativeClaimed(leaf.account, leaf.epoch), IERC20(leaf.token).balanceOf(leaf.account));
        vm.expectRevert("Rewards/nothing-to-claim");
        distributor.claim(leaf.epoch, leaf.account, leaf.token, leaf.cumulativeAmount, root, leaf.proof);
    }

    /* ========== HARDCODED CLAIM TESTS ========== */
    // Hardcoded claim tests to sanity check against the file-based tests
    function testClaim() public {
        bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;

        uint256 epoch = 1;
        address account = 0x1111111111111111111111111111111111111111;
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
        uint256 cumulativeAmount = 1000000000000000000000; // First claim 1000 tokens

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194;
        proof[1] = 0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008;
        proof[2] = 0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe;
        proof[3] = 0xd3e89f852744a1795a80bb9ca20e1fc04b3362c3b32c704697581b2ac0aeee08;

        distributor.setMerkleRoot(root);

        vm.prank(account);
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
        assertEq(distributor.cumulativeClaimed(account, epoch), IERC20(token).balanceOf(account));
    }

    function testCumulativeClaim() public {
        bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;

        uint256 epoch = 1;
        address account = 0x1111111111111111111111111111111111111111;
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
        uint256 cumulativeAmount = 1000000000000000000000; // First claim 1000 tokens

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194;
        proof[1] = 0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008;
        proof[2] = 0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe;
        proof[3] = 0xd3e89f852744a1795a80bb9ca20e1fc04b3362c3b32c704697581b2ac0aeee08;

        distributor.setMerkleRoot(root);

        vm.prank(account);
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
        assertEq(distributor.cumulativeClaimed(account, epoch), IERC20(token).balanceOf(account));

        // Set new root
        root = 0x3ad180d45b269158a2a43cd36b90dec892aeaf3b841eff43869286d542fe0f98;

        // Second claim
        cumulativeAmount = 1500000000000000000000; // Second claim 1500-1000=500 tokens
        proof[0] = 0x33e3c31aee3e738a8d300e6611c4b026403a6e68da3e93056e5168d79639d4b6;
        proof[1] = 0x0b1ae75516e2ca79d7e3c7b4b8025d10e0a2241e8f4245ba15e2c3f2e1946633;
        proof[2] = 0x66e2eab7a691f0a57807aaafa91b616ed48fe85d9b1b97f690c864a883d7ef28;
        proof[3] = 0xf6442853be236c0988a1b18b85479c6d9fac0e1ac92814a7dea8d7db78d3d221;

        distributor.setMerkleRoot(root);

        vm.prank(account);
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
        assertEq(distributor.cumulativeClaimed(account, epoch), IERC20(token).balanceOf(account));
    }

    function testClaimInvalidAccount(address account_) public {
        bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;

        uint256 epoch = 1;
        address account = 0x1111111111111111111111111111111111111111;
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
        uint256 cumulativeAmount = 1000000000000000000000; // First claim 1000 tokens

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194;
        proof[1] = 0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008;
        proof[2] = 0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe;
        proof[3] = 0xd3e89f852744a1795a80bb9ca20e1fc04b3362c3b32c704697581b2ac0aeee08;

        distributor.setMerkleRoot(root);

        vm.assume(account_ != account);
        vm.prank(account_);
        vm.expectRevert("Rewards/invalid-account");
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
    }

    function testClaimFailInvalidProof(bytes32 proof_) public {
        bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;

        uint256 epoch = 1;
        address account = 0x1111111111111111111111111111111111111111;
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
        uint256 cumulativeAmount = 1000000000000000000000; // First claim 1000 tokens

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194;
        proof[1] = 0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008;
        proof[2] = 0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe;
        proof[3] = 0xd3e89f852744a1795a80bb9ca20e1fc04b3362c3b32c704697581b2ac0aeee08;

        vm.assume(proof_ != proof[3]);
        proof[3] = proof_;

        distributor.setMerkleRoot(root);

        vm.prank(account);
        vm.expectRevert("Rewards/invalid-proof");
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
    }

    function testClaimInvalidRoot(bytes32 newRoot_) public {
        bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;
        vm.assume(root != newRoot_);

        uint256 epoch = 1;
        address account = 0x1111111111111111111111111111111111111111;
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
        uint256 cumulativeAmount = 1000000000000000000000; // First claim 1000 tokens

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194;
        proof[1] = 0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008;
        proof[2] = 0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe;
        proof[3] = 0xd3e89f852744a1795a80bb9ca20e1fc04b3362c3b32c704697581b2ac0aeee08;

        distributor.setMerkleRoot(root);

        bytes32 newRoot = newRoot_;
        distributor.setMerkleRoot(newRoot);
        vm.prank(account);
        vm.expectRevert("Rewards/merkle-root-was-updated");
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
    }

    function testClaimInvalidAmount(uint256 amount) public {
        vm.assume(amount != 1000000000000000000000);

        bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;

        uint256 epoch = 1;
        address account = 0x1111111111111111111111111111111111111111;
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
        uint256 cumulativeAmount = amount;

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194;
        proof[1] = 0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008;
        proof[2] = 0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe;
        proof[3] = 0xd3e89f852744a1795a80bb9ca20e1fc04b3362c3b32c704697581b2ac0aeee08;

        distributor.setMerkleRoot(root);

        vm.prank(account);
        vm.expectRevert("Rewards/invalid-proof");
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
    }

    function testClaimInvalidEpoch(uint256 epoch_) public {
        bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;

        uint256 epoch = epoch_;
        address account = 0x1111111111111111111111111111111111111111;
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
        uint256 cumulativeAmount = 1000000000000000000000;

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194;
        proof[1] = 0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008;
        proof[2] = 0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe;
        proof[3] = 0xd3e89f852744a1795a80bb9ca20e1fc04b3362c3b32c704697581b2ac0aeee08;

        distributor.setMerkleRoot(root);
        distributor.setEpochClosed(epoch, true);

        vm.prank(account);
        vm.expectRevert("Rewards/epoch-not-enabled");
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
    }

    function testNothingToClaim() public {
        bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;

        uint256 epoch = 1;
        address account = 0x1111111111111111111111111111111111111111;
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
        uint256 cumulativeAmount = 1000000000000000000000; // First claim 1000 tokens

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194;
        proof[1] = 0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008;
        proof[2] = 0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe;
        proof[3] = 0xd3e89f852744a1795a80bb9ca20e1fc04b3362c3b32c704697581b2ac0aeee08;

        distributor.setMerkleRoot(root);

        vm.prank(account);
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
        vm.prank(account);
        vm.expectRevert("Rewards/nothing-to-claim");
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
    }
}
