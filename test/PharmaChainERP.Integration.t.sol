// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PharmaChainERPBase.t.sol";

contract PharmaChainERPIntegrationTest is PharmaChainERPBase {
    function testShipAndReceiveHappyPath() public {
        uint256 batchId = _releasedBatch(1000);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 600);

        uint256 shipmentId = pharma.activeShipmentIdByBatch(batchId);
        assertEq(shipmentId, 1);
        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.IN_TRANSIT));
        assertEq(pharma.balanceOf(carrier, batchId), 600);
        assertEq(pharma.balanceOf(logistics, batchId), 400);

        vm.prank(destination);
        pharma.receiveShipment(batchId, 600, 0, "");

        assertEq(pharma.activeShipmentIdByBatch(batchId), 0);
        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.DELIVERED));
        assertEq(pharma.balanceOf(destination, batchId), 600);
        assertEq(pharma.balanceOf(carrier, batchId), 0);

        uint256[] memory shipmentIds = pharma.getShipmentIds(batchId);
        assertEq(shipmentIds.length, 1);

        PharmaChainERP.Shipment memory shipment = pharma.getShipment(batchId, 1);
        assertEq(shipment.qtyShipped, 600);
        assertEq(shipment.qtyReceived, 600);
        assertTrue(shipment.isCompleted);
    }

    function testReceiveShipmentWithLossBurnsAndAttachesLossReport() public {
        uint256 batchId = _releasedBatch(1000);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 1000);

        vm.prank(destination);
        pharma.receiveShipment(batchId, 990, 10, "10 frascos quebrados");

        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.DELIVERED));
        assertEq(pharma.balanceOf(destination, batchId), 990);
        assertEq(pharma.balanceOf(carrier, batchId), 0);

        (, string memory lossUri, string memory lossType,,) = pharma.batchDocuments(batchId, 1);
        assertEq(lossUri, "");
        assertEq(lossType, "LOSS_REPORT");
    }

    function testReceiveShipmentDiscrepancyMovesToQuarantine() public {
        uint256 batchId = _releasedBatch(500);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 500);

        vm.prank(destination);
        pharma.receiveShipment(batchId, 490, 5, "Avaria parcial");

        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.QUARANTINE));
        assertEq(pharma.balanceOf(carrier, batchId), 500);
        assertEq(pharma.balanceOf(destination, batchId), 0);
    }

    function testQuarantineCanBeReleasedByQuality() public {
        uint256 batchId = _releasedBatch(100);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 100);

        vm.prank(destination);
        pharma.receiveShipment(batchId, 90, 5, "Divergencia");
        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.QUARANTINE));

        vm.prank(quality);
        pharma.releaseBatch(batchId, keccak256("novo-coa"), "ipfs://coa/novo");
        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.RELEASED));
    }

    function testDeliveredBatchCanBeShippedAgain() public {
        uint256 batchId = _releasedBatch(200);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 100);

        vm.prank(destination);
        pharma.receiveShipment(batchId, 100, 0, "");

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 50);

        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.IN_TRANSIT));
        assertEq(pharma.activeShipmentIdByBatch(batchId), 2);
    }

    function testShipBatchRevertsWhenInvalid() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-SHIP", 100, 1);

        vm.prank(logistics);
        vm.expectRevert("Lote nao liberado");
        pharma.shipBatch(batchId, carrier, destination, 10);

        vm.prank(quality);
        pharma.releaseBatch(batchId, keccak256("coa"), "ipfs://coa/ship");

        vm.prank(logistics);
        vm.expectRevert("Destino sem LOGISTICS_ROLE");
        pharma.shipBatch(batchId, carrier, outsider, 10);

        vm.warp(_expDate(batchId) + 1);
        vm.prank(logistics);
        vm.expectRevert("ERRO: Lote vencido");
        pharma.shipBatch(batchId, carrier, destination, 10);
    }

    function testShipBatchRevertsIfAnotherShipmentIsActive() public {
        uint256 batchId = _releasedBatch(1000);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 100);

        vm.prank(logistics);
        vm.expectRevert("Ja existe remessa ativa");
        pharma.shipBatch(batchId, carrier, destination, 50);
    }

    function testShipBatchValidationRevertsForInputsAndBalance() public {
        uint256 batchId = _releasedBatch(100);

        vm.prank(logistics);
        vm.expectRevert("Carrier invalido");
        pharma.shipBatch(batchId, address(0), destination, 10);

        vm.prank(logistics);
        vm.expectRevert("Destino invalido");
        pharma.shipBatch(batchId, carrier, address(0), 10);

        vm.prank(logistics);
        vm.expectRevert("Quantidade invalida");
        pharma.shipBatch(batchId, carrier, destination, 0);

        vm.prank(logistics);
        vm.expectRevert("Saldo insuficiente");
        pharma.shipBatch(batchId, carrier, destination, 1000);
    }

    function testReceiveShipmentRevertsForWrongDestinationOrInvalidMass() public {
        uint256 batchId = _releasedBatch(200);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 200);

        pharma.grantRole(pharma.LOGISTICS_ROLE(), outsider);
        vm.prank(outsider);
        vm.expectRevert("Apenas o destino correto pode receber");
        pharma.receiveShipment(batchId, 200, 0, "");

        vm.prank(destination);
        vm.expectRevert("Quantidades invalidas");
        pharma.receiveShipment(batchId, 201, 0, "");

        vm.prank(destination);
        vm.expectRevert("Motivo da perda obrigatorio");
        pharma.receiveShipment(batchId, 190, 10, "");
    }

    function testReceiveShipmentRevertsNoActiveAndWrongStatus() public {
        uint256 batchId = _releasedBatch(120);

        vm.prank(destination);
        vm.expectRevert("Nao ha remessa ativa");
        pharma.receiveShipment(batchId, 120, 0, "");

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 120);

        vm.prank(quality);
        pharma.executeRecall(batchId, "Recall durante transporte");

        vm.prank(destination);
        vm.expectRevert("Carga nao esta em transito");
        pharma.receiveShipment(batchId, 120, 0, "");
    }

    function testGetShipmentRevertsForUnknownShipment() public {
        uint256 batchId = _releasedBatch(100);

        vm.prank(logistics);
        pharma.shipBatch(batchId, carrier, destination, 50);

        vm.expectRevert("Remessa inexistente");
        pharma.getShipment(batchId, 999);
    }

    function testPauseBlocksOperationalFunctions() public {
        pharma.pauseContract();

        vm.prank(logistics);
        vm.expectRevert("Pausable: paused");
        pharma.mintBatch("GTIN", 100, 10);

        vm.prank(oracle);
        vm.expectRevert("Pausable: paused");
        pharma.updateActorLicense(logistics, true, "REF");

        pharma.unpauseContract();

        vm.prank(logistics);
        pharma.mintBatch("GTIN", 100, 10);
    }
}
