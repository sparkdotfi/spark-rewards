// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {SparkRewards} from "../src/SparkRewards.sol";

contract Deploy is Script {
    bytes32 public constant EPOCH_ROLE       = keccak256("EPOCH_ROLE");
    bytes32 public constant MERKLE_ROOT_ROLE = keccak256("MERKLE_ROOT_ROLE");

    function run() external {
        // Read the config file
        string memory config = vm.readFile("./script/config.json");

        // Parse the JSON file vars
        address admin = vm.parseJsonAddress(config, ".admin");
        address wallet = vm.parseJsonAddress(config, ".wallet");
        address epochAdmin = vm.parseJsonAddress(config, ".epoch_role");
        address merkleRootAdmin = vm.parseJsonAddress(config, ".merkle_role");

        console.log("Deploying SparkRewards contract with the following parameters:");
        console.log("Admin:", admin);
        console.log("Wallet:", wallet);
        console.log("Epoch Admin:", epochAdmin);
        console.log("Merkle Root Admin:", merkleRootAdmin);
        vm.startBroadcast();

        // Deploy the contract using the parsed admin address
        SparkRewards rewards = new SparkRewards(msg.sender);

        // Set the wallet using the parsed wallet address
        rewards.setWallet(wallet);

        // Grant the roles using the parsed role addresses
        rewards.grantRole(EPOCH_ROLE, epochAdmin);
        rewards.grantRole(MERKLE_ROOT_ROLE, merkleRootAdmin);

        // Transfer the ownership to the admin address
        rewards.grantRole(rewards.DEFAULT_ADMIN_ROLE(), admin);

        // Revoke admin role from deployer
        rewards.revokeRole(rewards.DEFAULT_ADMIN_ROLE(), msg.sender);

        vm.stopBroadcast();

        // Log the deployed contract address
        console.log("Rewards deployed at:", address(rewards));
    }
}