// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./PharmaChainERPBase.t.sol";

contract PharmaChainERPSecurityTest is PharmaChainERPBase {
    function testDirectTransfersAreBlocked() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-BLOCK", 100, 5);

        vm.prank(logistics);
        vm.expectRevert("Transferencia direta bloqueada");
        pharma.safeTransferFrom(logistics, carrier, batchId, 10, "");
    }

    function testSafeBatchTransferFromBlocked() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-BATCH-BLOCK", 100, 5);

        uint256[] memory ids = new uint256[](1);
        ids[0] = batchId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.prank(logistics);
        vm.expectRevert("Transferencia direta bloqueada");
        pharma.safeBatchTransferFrom(logistics, carrier, ids, amounts, "");
    }

    function testOnlyExistingBatchGuardOnPublicFunctions() public {
        vm.expectRevert("Lote inexistente");
        pharma.getShipmentIds(999);

        vm.expectRevert("Lote inexistente");
        pharma.attachFiscalDoc(999, keccak256("nfe"), "ipfs://nfe/unknown");
    }

    function testSetURIAndUpgradeAreAdminOnly() public {
        vm.prank(outsider);
        vm.expectRevert();
        pharma.setURI("ipfs://novo/{id}");

        pharma.setURI("ipfs://novo/{id}");
        assertEq(pharma.uri(1), "ipfs://novo/{id}");

        PharmaChainERP newImplementation = new PharmaChainERP();

        vm.prank(outsider);
        vm.expectRevert();
        pharma.upgradeTo(address(newImplementation));

        pharma.upgradeTo(address(newImplementation));
    }

    function testCriticalOperationsRequireRoles() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-RBAC", 100, 20);

        vm.prank(outsider);
        vm.expectRevert();
        pharma.releaseBatch(batchId, keccak256("coa"), "ipfs://coa/x");

        vm.prank(outsider);
        vm.expectRevert();
        pharma.executeRecall(batchId, "x");

        vm.prank(outsider);
        vm.expectRevert();
        pharma.shipBatch(batchId, carrier, destination, 10);
    }

    function testRejectedBatchCanTransitionToRecallAndRejectSameStatus() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-RECALL", 100, 20);

        vm.prank(quality);
        pharma.rejectBatch(batchId, "Falha QA", bytes32(0), "");
        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.REJECTED));

        vm.prank(quality);
        pharma.executeRecall(batchId, "Recall regulatorio");
        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.RECALL));

        vm.prank(quality);
        vm.expectRevert("Status ja definido");
        pharma.executeRecall(batchId, "Repetido");
    }

    function testInternalTransitionGuardForInvalidPath() public {
        PharmaChainERPHarness harness = new PharmaChainERPHarness();
        harness.exposedSetBatchStatus(1, PharmaChainERP.BatchStatus.RECALL);

        vm.expectRevert("Transicao de status invalida");
        harness.exposedChangeStatus(1, PharmaChainERP.BatchStatus.DELIVERED, "invalido");
    }

    function testReentrancyBlockedDuringShipCallback() public {
        uint256 batchId = _releasedBatch(150);

        MaliciousCarrierReceiver attacker = new MaliciousCarrierReceiver(pharma);
        pharma.grantRole(pharma.LOGISTICS_ROLE(), address(attacker));

        attacker.configure(batchId, destination);

        vm.prank(logistics);
        pharma.shipBatch(batchId, address(attacker), destination, 100);

        assertTrue(attacker.reenterAttempted());
        assertFalse(attacker.reenterSucceeded());
        assertEq(pharma.activeShipmentIdByBatch(batchId), 1);
        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.IN_TRANSIT));
    }
}

contract MaliciousCarrierReceiver is IERC1155Receiver {
    PharmaChainERP internal immutable pharma;

    uint256 internal targetBatchId;
    address internal targetDestination;

    bool internal attempted;
    bool internal succeeded;

    constructor(PharmaChainERP _pharma) {
        pharma = _pharma;
    }

    function configure(uint256 batchId, address destination) external {
        targetBatchId = batchId;
        targetDestination = destination;
    }

    function reenterAttempted() external view returns (bool) {
        return attempted;
    }

    function reenterSucceeded() external view returns (bool) {
        return succeeded;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external override returns (bytes4) {
        if (!attempted) {
            attempted = true;

            try pharma.shipBatch(targetBatchId, address(this), targetDestination, 1) {
                succeeded = true;
            } catch {
                succeeded = false;
            }
        }

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
