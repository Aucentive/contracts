// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Script.sol";
import "../contracts/FTDataAsserter.sol";

contract DeployFTDataAsserter is Script {
  function run() external {
    // Base Goerli
    address bondToken = address(0xEF8b46765ae805537053C59f826C3aD61924Db45);
    address optimisticOracleV3 = address(
      0x1F4dC6D69E3b4dAC139E149E213a7e863a813466
    );
    address aucentiveHub = address(0x85a5625a7614682918dE6EE382a6A39043cE294B);

    vm.startBroadcast();

    new FTDataAsserter(bondToken, optimisticOracleV3, aucentiveHub);

    vm.stopBroadcast();
  }
}
