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

    struct Reward {
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
        token1.transfer(address(distributor), 1_000_000 * 1e18);
        token2.transfer(address(distributor), 1_000_000 * 1e18);
        distributor.enableEpoch(2);
        distributor.enableEpoch(3);
    }

    function parseMerkleRoot(string memory json) public pure returns (bytes32) {
        return vm.parseJsonBytes32(json, ".root");
    }
    function parseReward(uint256 index, string memory json) public pure returns (Reward memory) {
        // Use the index parameter to dynamically access the values
        string memory indexPath = string(abi.encodePacked(".values[", vm.toString(index), "]"));

        uint256 epoch = uint256(vm.parseJsonUint(json, string(abi.encodePacked(indexPath, ".epoch"))));
        address account = vm.parseJsonAddress(json, string(abi.encodePacked(indexPath, ".account")));
        address token = vm.parseJsonAddress(json, string(abi.encodePacked(indexPath, ".token")));
        uint256 cumulativeAmount = uint256(
            vm.parseJsonUint(json, string(abi.encodePacked(indexPath, ".cumulativeAmount")))
        );

        // Parse the proof
        bytes32[] memory proof = abi.decode(
            vm.parseJson(json, string(abi.encodePacked(indexPath, ".proof"))),
            (bytes32[])
        );

        return Reward(epoch, account, token, cumulativeAmount, proof);
    }

    // function getValuesLength(string memory json) public pure returns (uint256) {
    //     // Parse the values array
    //     bytes memory valuesArray = vm.parseJson(json, ".values");
    //     // Decode the array to get its length
    //     return abi.decode(valuesArray, (bytes[])).length;
    // }

    function testIncrementEpoch() public {
        uint256 oldEpoch = distributor.epoch();
        distributor.incrementEpoch();
        assertEq(distributor.epoch(), oldEpoch + 1);
    }

    function testDisableEpoch() public {
        uint256 epoch = distributor.epoch();
        distributor.disableEpoch(epoch);
        assert(!distributor.epochEnabled(epoch));
    }

    function testEnableEpoch() public {
        uint256 epoch = distributor.epoch() + 1;
        distributor.enableEpoch(epoch);
        assert(distributor.epochEnabled(epoch));
    }

    function testIncrementOnlyOwner(address account) public {
        vm.assume(account != address(this));
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", account));
        distributor.incrementEpoch();
    }

    function testEnableEpochOnlyOwner(address account) public {
        vm.assume(account != address(this));
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", account));
        distributor.enableEpoch(1);
    }

    function testDisableEpochOnlyOwner(address account) public {
        vm.assume(account != address(this));
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", account));
        distributor.disableEpoch(1);
    }


    function testSetMerkleRoot(string memory seed) public {
        bytes32 newRoot = keccak256(abi.encodePacked(seed));
        distributor.setMerkleRoot(newRoot);
        assertEq(distributor.merkleRoot(), newRoot);
    }

    function testSetMerkleRootInvalidSender(address account) public {
        vm.assume(account != address(this));
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            account
        ));
        distributor.setMerkleRoot(0);
    }

    function testClaimFromFile(uint256 index) public {
        index = bound(index, 0, 11);

        string memory json = vm.readFile("test/data/exampleTree1.json");
        bytes32 root = parseMerkleRoot(json);
        Reward memory reward = parseReward(index, json);
        
        distributor.setMerkleRoot(root);

        vm.prank(reward.account);
        distributor.claim(reward.epoch, reward.account, reward.token, reward.cumulativeAmount, root, reward.proof);
        assertEq(distributor.cumulativeClaimed(reward.account, reward.epoch), IERC20(reward.token).balanceOf(reward.account));
    }

    function testClaimCumulativeFromFile(uint256 index) public {
        // Note both files being imported in this test must keep the same ordering of rewards to work
        index = bound(index, 0, 11);
        string memory json = vm.readFile("test/data/exampleTree1.json");
        bytes32 root = parseMerkleRoot(json);
        Reward memory reward = parseReward(index, json);
        
        distributor.setMerkleRoot(root);

        vm.prank(reward.account);
        distributor.claim(reward.epoch, reward.account, reward.token, reward.cumulativeAmount, root, reward.proof);
        assertEq(distributor.cumulativeClaimed(reward.account, reward.epoch), IERC20(reward.token).balanceOf(reward.account));

        json = vm.readFile("test/data/exampleTree2.json");
        root = parseMerkleRoot(json);
        reward = parseReward(index, json);

        distributor.setMerkleRoot(root);
        vm.prank(reward.account);
        distributor.claim(reward.epoch, reward.account, reward.token, reward.cumulativeAmount, root, reward.proof);
        assertEq(distributor.cumulativeClaimed(reward.account, reward.epoch), IERC20(reward.token).balanceOf(reward.account));
    }

    function testClaimFromFileInvalidEpoch(uint256 index) public {
        index = bound(index, 0, 11);

        string memory json = vm.readFile("test/data/exampleTree1.json");
        bytes32 root = parseMerkleRoot(json);
        Reward memory reward = parseReward(index, json);
        
        distributor.setMerkleRoot(root);
        distributor.disableEpoch(reward.epoch);
        vm.prank(reward.account);
        vm.expectRevert("Rewards/epoch-not-enabled");
        distributor.claim(reward.epoch, reward.account, reward.token, reward.cumulativeAmount, root, reward.proof);
    }

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
        cumulativeAmount = 1500000000000000000000;  // Second claim 1500-1000=500 tokens
        proof[0] = 0x33e3c31aee3e738a8d300e6611c4b026403a6e68da3e93056e5168d79639d4b6;
        proof[1] = 0x0b1ae75516e2ca79d7e3c7b4b8025d10e0a2241e8f4245ba15e2c3f2e1946633;
        proof[2] = 0x66e2eab7a691f0a57807aaafa91b616ed48fe85d9b1b97f690c864a883d7ef28;
        proof[3] = 0xf6442853be236c0988a1b18b85479c6d9fac0e1ac92814a7dea8d7db78d3d221;

        distributor.setMerkleRoot(root);

        vm.prank(account);
        distributor.claim(epoch, account, token, cumulativeAmount, root, proof);
        assertEq(distributor.cumulativeClaimed(account, epoch), IERC20(token).balanceOf(account));
    }

    function testClaimFailInvalidProof() public {
        bytes32 root = 0xdf1c8acd41bc6fbedd45b9ac771e141b06ed63450154099d2107ca6b7c60f3b4;

        uint256 epoch = 1;
        address account = 0x1111111111111111111111111111111111111111;
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
        uint256 cumulativeAmount = 1000000000000000000000; // First claim 1000 tokens

        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x76f6509713b1c5f1badb44e594485cccf676833f7a1eb10ec22a80905ec00194;
        proof[1] = 0xd0c587636eaf9e3a18bf755b5eaf2ca1ae41c41a5714fea94a58b733081a1008;
        proof[2] = 0xca8123d02c6601929d5d5c05002003563dda41236b325fdbc3e56e0665f3b9fe;
        proof[3] = 0x0000000000000000000000000000000000000000000000000000000000000000;

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
        uint256 cumulativeAmount = amount; // First claim 1000 tokens

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

    function testClaimNothingToClaim() public {
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
