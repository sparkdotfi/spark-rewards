// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {Rewards} from "../src/Rewards.sol";

contract Deploy is Script {

    function run() external {
        vm.startBroadcast();
        Rewards rewards = new Rewards(msg.sender); //TODO: change this to read admin from a file
        vm.stopBroadcast();
        console.log("Rewards deployed at:", address(rewards));
    }
}
