// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {Rewards} from "../src/Rewards.sol";

contract Deploy is Script {
    function run() external {
        // Read the config file
        string memory config = vm.readFile("./script/config.json");

        // Parse the JSON file directly to address
        address admin = vm.parseJsonAddress(config, ".admin");
        address wallet = vm.parseJsonAddress(config, ".wallet");
        bytes32 merkleRoot = vm.parseJsonBytes32(config, ".root");

        console.log("Deploying Rewards contract with the following parameters:");
        console.log("Admin:", admin);
        console.log("Wallet:", wallet);
        console.log("Merkle Root:");
        console.logBytes32(merkleRoot);
        vm.startBroadcast();

        // Deploy the contract using the parsed admin address
        Rewards rewards = new Rewards();

        // Set the wallet using the parsed wallet address
        rewards.setWallet(wallet);

        // Set the merkle root using the parsed merkle root
        rewards.setMerkleRoot(merkleRoot);

        // Transfer the ownership to the admin
        rewards.grantRole(rewards.DEFAULT_ADMIN_ROLE(), admin);

        vm.stopBroadcast();

        // Log the deployed contract address
        console.log("Rewards deployed at:", address(rewards));
    }
}