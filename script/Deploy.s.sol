// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {Rewards} from "../src/Rewards.sol";

contract Deploy is Script {
    bytes32 public constant EPOCH_ROLE       = keccak256("EPOCH_ROLE");
    bytes32 public constant MERKLE_ROOT_ROLE = keccak256("MERKLE_ROOT_ROLE");
    bytes32 public constant WALLET_ROLE      = keccak256("WALLET_ROLE");

    function run() external {
        // Read the config file
        string memory config = vm.readFile("./script/config.json");

        // Parse the JSON file vars
        address admin = vm.parseJsonAddress(config, ".admin");
        address wallet = vm.parseJsonAddress(config, ".wallet");
        bytes32 merkleRoot = vm.parseJsonBytes32(config, ".root");

        address epochAdmin = vm.parseJsonAddress(config, ".epoch_role");
        address merkleRootAdmin = vm.parseJsonAddress(config, ".merkle_role");
        address walletAdmin = vm.parseJsonAddress(config, ".wallet_role");

        console.log("Deploying Rewards contract with the following parameters:");
        console.log("Admin:", admin);
        console.log("Wallet:", wallet);
        console.log("Epoch Admin:", epochAdmin);
        console.log("Merkle Root Admin:", merkleRootAdmin);
        console.log("Wallet Admin:", walletAdmin);
        console.log("Merkle Root:");
        console.logBytes32(merkleRoot);
        vm.startBroadcast();

        // Deploy the contract using the parsed admin address
        Rewards rewards = new Rewards(msg.sender);

        // Set the wallet using the parsed wallet address
        rewards.setWallet(wallet);

        // Set the merkle root using the parsed merkle root
        rewards.setMerkleRoot(merkleRoot);

        // Grant the roles using the parsed role addresses
        rewards.grantRole(EPOCH_ROLE, epochAdmin);
        rewards.grantRole(MERKLE_ROOT_ROLE, merkleRootAdmin);
        rewards.grantRole(WALLET_ROLE, walletAdmin);

        // Transfer the ownership to the admin
        rewards.grantRole(rewards.DEFAULT_ADMIN_ROLE(), admin);

        vm.stopBroadcast();

        // Log the deployed contract address
        console.log("Rewards deployed at:", address(rewards));
    }
}