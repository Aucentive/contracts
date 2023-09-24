// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Script.sol";
import "../contracts/AucentiveHub.sol";

contract DeployAucentiveHub is Script {
  function run() external {
    vm.startBroadcast();

    (address gateway, address gasService, address usdc) = getAddresses();

    require(
      gateway != address(0x0) &&
        gasService != address(0x0) &&
        usdc != address(0x0),
      "Invalid addresses"
    );

    new AucentiveHub(gateway, gasService, usdc);

    vm.stopBroadcast();
  }

  function getAddresses()
    public
    view
    returns (address gateway, address gasService, address usdc)
  {
    if (block.chainid == 8453) {
      // Base Mainnet
      gateway = address(0xe432150cce91c13a887f7D836923d5597adD8E31);
      gasService = address(0x2d5d7d31F671F86C782533cc367F14109a082712);
      usdc = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    }

    if (block.chainid == 84531) {
      // Base Goerli
      gateway = address(0xe432150cce91c13a887f7D836923d5597adD8E31);
      gasService = address(0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6);
      usdc = address(0xF175520C52418dfE19C8098071a252da48Cd1C19);
    }
  }
}
