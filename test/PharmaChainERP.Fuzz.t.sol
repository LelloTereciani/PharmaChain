// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PharmaChainERPBase.t.sol";

contract PharmaChainERPFuzzTest is PharmaChainERPBase {
    function testFuzzMintBatchStoresExpectedData(uint96 qty, uint16 validityDays) public {
        uint256 boundedQty = bound(uint256(qty), 1, 1_000_000);
        uint256 boundedDays = bound(uint256(validityDays), 1, 3650);

        uint256 batchId = _mintBatchAs(logistics, "GTIN-FUZZ", boundedQty, boundedDays);

        (
            ,
            uint256 mfgDate,
            uint256 expDate,
            uint256 productionQty,
            PharmaChainERP.BatchStatus status,
            
        ) = pharma.batches(batchId);

        assertEq(productionQty, boundedQty);
        assertEq(uint256(status), uint256(PharmaChainERP.BatchStatus.IN_PRODUCTION));
        assertEq(expDate, mfgDate + (boundedDays * 1 days));
    }

    function testFuzzReceiveShipmentMassBalanceDelivered(uint96 shipped, uint96 received) public {
        uint256 boundedShipped = bound(uint256(shipped), 1, 1_000_000);
        uint256 boundedReceived = bound(uint256(received), 0, boundedShipped);
        uint256 loss = boundedShipped - boundedReceived;

        uint256 batchId = _releasedBatch(boundedShipped);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, boundedShipped);

        string memory reason = loss > 0 ? "Perda operacional" : "";

        vm.prank(destination);
        pharma.receiveShipment(batchId, boundedReceived, loss, reason);

        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.DELIVERED));
        assertEq(pharma.balanceOf(destination, batchId), boundedReceived);
        assertEq(pharma.balanceOf(carrier, batchId), 0);
    }

    function testFuzzReceiveShipmentDiscrepancyGoesQuarantine(uint96 shipped, uint96 received, uint96 lost) public {
        uint256 boundedShipped = bound(uint256(shipped), 2, 1_000_000);
        uint256 boundedReceived = bound(uint256(received), 0, boundedShipped - 1);
        uint256 maxLost = boundedShipped - boundedReceived - 1;
        uint256 boundedLost = bound(uint256(lost), 0, maxLost);

        uint256 batchId = _releasedBatch(boundedShipped);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, boundedShipped);

        vm.prank(destination);
        pharma.receiveShipment(batchId, boundedReceived, boundedLost, boundedLost > 0 ? "Perda" : "");

        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.QUARANTINE));
        assertEq(pharma.balanceOf(carrier, batchId), boundedShipped);
    }
}
