// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {MockERC20} from "./mock/MockERC20.sol";
import {AucentiveHub} from "../contracts/AucentiveHub.sol";
import {AucentiveSpoke} from "../contracts/AucentiveSpoke.sol";

contract AucentiveTest is Test {
  event ServicePaid(bytes32 serviceId, uint256 payAmount);
  event ServiceReplied(bytes32 serviceId);
  event ServiceCancelled(bytes32 serviceId);

  MockERC20 USDC; // mock ERC20 token used for "all" chains

  AucentiveHub aucHub;
  AucentiveSpoke aucSpoke;

  //   function setUpSource() public override {
  //     if (address(USDC) == address(0)) {
  //       USDC = new MockERC20();

  //       // "Changes made to the state of this account will be kept when switching forks"
  //       vm.makePersistent(address(USDC));
  //     }

  //     // Arbitrum
  //     aucSpoke = new AucentiveSpoke(
  //       address(gateway),
  //       address(gasRelayer),
  //       address(USDC)
  //     );
  //     vm.makePersistent(address(aucSpoke));
  //   }

  //   function setUpTarget() public override {
  //     if (address(USDC) == address(0)) {
  //       USDC = new MockERC20();
  //       vm.makePersistent(address(USDC));
  //     }

  //     // Optimism
  //     aucHub = new AucentiveHub(
  //       address(gateway),
  //       address(gasRelayer),
  //       address(USDC)
  //     );
  //     vm.makePersistent(address(aucHub));
  //   }

  function setUp() public {
    USDC = new MockERC20();

    aucHub = new AucentiveHub(address(0x1), address(0x1), address(USDC), address(0x1));
  }

  function testServiceCreate() public {
    bytes32 serviceId = bytes32(uint256(1));
    uint256 minAmount = 100;

    vm.recordLogs();

    aucHub.createService(
      serviceId,
      minAmount,
      uint64(3600) // 1 hour
    );

    assertEq(aucHub.services(serviceId).minAmount, minAmount);
    assertTrue(
      aucHub.services(serviceId).status ==
        AucentiveHub.ServiceStatus.PENDING_PAYMENT
    );
  }

  function testServicePaymentSuccess() public {
    bytes32 serviceId = bytes32(uint256(1));
    uint256 payAmount = 100;

    vm.recordLogs();

    aucHub.createService(
      serviceId,
      payAmount,
      uint64(3600) // 1 hour
    );

    USDC.mint(address(this), payAmount);
    USDC.approve(address(aucHub), payAmount);

    aucHub.payForService(serviceId, payAmount);

    assertEq(aucHub.services(serviceId).paidAmount, payAmount);
    assertTrue(
      aucHub.services(serviceId).status ==
        AucentiveHub.ServiceStatus.PENDING_COMPLETION
    );

    assertEq(USDC.balanceOf(address(this)), 0);
    assertEq(USDC.balanceOf(address(aucHub)), payAmount);
  }

  function testServiceChangeStatus() public {
    bytes32 serviceId = bytes32(uint256(1));
    uint256 payAmount = 100;

    vm.recordLogs();

    aucHub.createService(
      serviceId,
      payAmount,
      uint64(3600) // 1 hour
    );

    aucHub.modifyServiceStatus(
      serviceId,
      AucentiveHub.ServiceStatus.COMPLETED,
      address(this),
      address(this)
    );

    assertTrue(
      aucHub.services(serviceId).status == AucentiveHub.ServiceStatus.COMPLETED
    );
  }

  function testServicePayoutSuccess() public {
    bytes32 serviceId = bytes32(uint256(1));
    uint256 payAmount = 100;

    vm.recordLogs();

    aucHub.createService(
      serviceId,
      payAmount,
      uint64(3600) // 1 hour
    );

    USDC.mint(address(this), payAmount);
    USDC.approve(address(aucHub), payAmount);

    aucHub.payForService(serviceId, payAmount);

    aucHub.modifyServiceStatus(
      serviceId,
      AucentiveHub.ServiceStatus.COMPLETED,
      address(this),
      address(this)
    );

    uint256 balanceBefore = USDC.balanceOf(address(this));

    aucHub.withdrawBalance();
    assertEq(USDC.balanceOf(address(this)) - balanceBefore, payAmount);
  }

  //   function testCrossChainEmailPayment() public {
  //     uint256 cost = aucSpoke.quoteEmailPayment(targetChain);

  //     bytes32 serviceId = bytes32(uint256(1));
  //     uint256 minAmount = 100;

  //     vm.recordLogs();

  //     vm.selectFork(targetFork);
  //     aucHub.createService(
  //       serviceId,
  //       minAmount,
  //       uint64(3600) // 1 hour
  //     );

  //     vm.selectFork(sourceFork);
  //     aucSpoke.sendEmailPayment{value: cost}(
  //       targetChain,
  //       address(aucHub),
  //       serviceId,
  //       minAmount
  //     );

  //     performDelivery();
  //     // vm.selectFork(targetFork);
  //   }
}
