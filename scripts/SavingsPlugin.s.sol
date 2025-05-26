// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {RoundUpSavingsPlugin} from "../contracts/plugins/savings/RoundUpSavingsPlugin.sol";

contract DeplpySavingsPlugin is Script {
    function run() public {
        vm.startBroadcast();

        // Deploy contract
        RoundUpSavingsPlugin savingsPlugin = new RoundUpSavingsPlugin();
        address deployedAddress = address(savingsPlugin);

        console.log("Deployed SavingsPlugin at:", deployedAddress);

        // Save the address to a file using vm.writeFile
        string memory filePath = "deployments/SavingsPlugin.json";
        string memory jsonContent = string.concat(
            '{ "CustomSessionKeyPluginAddress": "',
            vm.toString(deployedAddress),
            '" }'
        );
        
        vm.writeFile(filePath, jsonContent);

        vm.stopBroadcast();
    }
}
