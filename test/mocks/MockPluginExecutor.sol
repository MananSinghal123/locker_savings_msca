// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {IPluginExecutor} from "../../contracts/interfaces/IPluginExecutor.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract MockPluginExecutor is IPluginExecutor {
    address public account;

    function setAccount(address _account) external {
        account = _account;
    }

    function executeFromPluginExternal(
        address target,
        uint256 value,
        bytes calldata data
    ) external payable override returns (bytes memory) {
        // Decode the transfer data
        (address recipient, uint256 amount) = abi.decode(data[4:], (address, uint256));
        
        // Execute the transfer from the account
        IERC20(target).transferFrom(account, recipient, amount);
        
        return "";
    }

    function executeFromPlugin(bytes calldata data) external payable override returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call{value: msg.value}(data);
        require(success, "MockPluginExecutor: call failed");
        return returnData;
    }
} 