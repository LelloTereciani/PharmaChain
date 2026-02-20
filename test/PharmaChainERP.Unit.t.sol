// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PharmaChainERPBase.t.sol";

contract PharmaChainERPUnitTest is PharmaChainERPBase {
    function testInitializeSetsExpectedRoles() public view {
        assertTrue(pharma.hasRole(pharma.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(pharma.hasRole(pharma.ADMIN_ROLE(), address(this)));
        assertEq(pharma.getRoleAdmin(pharma.QUALITY_ROLE()), pharma.ADMIN_ROLE());
        assertEq(pharma.getRoleAdmin(pharma.LOGISTICS_ROLE()), pharma.ADMIN_ROLE());
    }

    function testInitializeCannotBeCalledTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        pharma.initialize(BASE_URI);
    }

    function testMintBatchStoresDataAndBalance() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-001", 1000, 30);

        (
            string memory gtin,
            ,
            uint256 expDate,
            uint256 productionQty,
            PharmaChainERP.BatchStatus status,
            
        ) = pharma.batches(batchId);

        assertEq(batchId, 1);
        assertEq(gtin, "GTIN-001");
        assertEq(pharma.balanceOf(logistics, batchId), 1000);
        assertEq(productionQty, 1000);
        assertEq(uint256(status), uint256(PharmaChainERP.BatchStatus.IN_PRODUCTION));
        assertGt(expDate, block.timestamp);
    }

    function testMintBatchRevertsForInvalidInput() public {
        vm.startPrank(logistics);

        vm.expectRevert("GTIN obrigatorio");
        pharma.mintBatch("", 1000, 30);

        vm.expectRevert("Quantidade invalida");
        pharma.mintBatch("GTIN", 0, 30);

        vm.expectRevert("Validade invalida");
        pharma.mintBatch("GTIN", 10, 0);

        vm.stopPrank();
    }

    function testMintBatchRespectsLicensingWhenEnabled() public {
        pharma.setLicensingEnforcement(true);

        vm.prank(logistics);
        vm.expectRevert("Licenca inativa");
        pharma.mintBatch("GTIN", 100, 30);

        vm.prank(oracle);
        pharma.updateActorLicense(logistics, true, "ANVISA-OK");

        vm.prank(logistics);
        pharma.mintBatch("GTIN", 100, 30);
    }

    function testReleaseBatchChangesStatusAndAttachesCOA() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-REL", 500, 20);

        vm.prank(quality);
        pharma.releaseBatch(batchId, keccak256("coa"), "ipfs://coa/1");

        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.RELEASED));

        (bytes32 docHash, string memory docUri, string memory docType,, address uploadedBy) = pharma.batchDocuments(batchId, 0);
        assertEq(docHash, keccak256("coa"));
        assertEq(docUri, "ipfs://coa/1");
        assertEq(docType, "COA");
        assertEq(uploadedBy, quality);
    }

    function testReleaseBatchValidationReverts() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-REL-VAL", 300, 20);

        vm.prank(quality);
        vm.expectRevert("Hash COA obrigatorio");
        pharma.releaseBatch(batchId, bytes32(0), "ipfs://coa/2");

        vm.prank(quality);
        vm.expectRevert("URI COA obrigatoria");
        pharma.releaseBatch(batchId, keccak256("coa-2"), "");

        vm.prank(quality);
        pharma.releaseBatch(batchId, keccak256("coa-2"), "ipfs://coa/2");

        vm.prank(quality);
        vm.expectRevert("Status invalido");
        pharma.releaseBatch(batchId, keccak256("coa-3"), "ipfs://coa/3");
    }

    function testRejectBatchWithEvidenceAttachesNCR() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-REJ", 200, 10);

        vm.prank(quality);
        pharma.rejectBatch(batchId, "Metais acima do limite", keccak256("ncr"), "ipfs://ncr/1");

        assertEq(uint256(_status(batchId)), uint256(PharmaChainERP.BatchStatus.REJECTED));

        (, string memory docUri, string memory docType,,) = pharma.batchDocuments(batchId, 0);
        assertEq(docUri, "ipfs://ncr/1");
        assertEq(docType, "NCR");
    }

    function testRejectBatchValidationReverts() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-REJ-VAL", 300, 20);

        vm.prank(quality);
        vm.expectRevert("Motivo obrigatorio");
        pharma.rejectBatch(batchId, "", bytes32(0), "");

        vm.prank(quality);
        vm.expectRevert("Hash evidencia obrigatorio");
        pharma.rejectBatch(batchId, "Nao conforme", bytes32(0), "ipfs://ncr/2");

        vm.prank(quality);
        vm.expectRevert("URI evidencia obrigatoria");
        pharma.rejectBatch(batchId, "Nao conforme", keccak256("ncr-2"), "");

        vm.prank(quality);
        pharma.releaseBatch(batchId, keccak256("coa"), "ipfs://coa/ok");

        vm.prank(quality);
        vm.expectRevert("Status invalido");
        pharma.rejectBatch(batchId, "Nao deveria", bytes32(0), "");
    }

    function testExecuteRecallSetsReasonAndStatus() public {
        uint256 batchId = _releasedBatch(1000);

        vm.prank(quality);
        pharma.executeRecall(batchId, "Contaminacao microbiologica");

        (, , , , PharmaChainERP.BatchStatus status, string memory recallReason) = pharma.batches(batchId);
        assertEq(uint256(status), uint256(PharmaChainERP.BatchStatus.RECALL));
        assertEq(recallReason, "Contaminacao microbiologica");
    }

    function testExecuteRecallValidationReverts() public {
        uint256 batchId = _releasedBatch(100);

        vm.prank(quality);
        vm.expectRevert("Motivo obrigatorio");
        pharma.executeRecall(batchId, "");
    }

    function testAttachFiscalDocOnlyProductionOrLogistics() public {
        uint256 batchId = _mintBatchAs(producer, "GTIN-FISC", 100, 15);

        vm.prank(outsider);
        vm.expectRevert("Acesso negado");
        pharma.attachFiscalDoc(batchId, keccak256("nfe"), "ipfs://nfe/1");

        vm.prank(producer);
        pharma.attachFiscalDoc(batchId, keccak256("nfe"), "ipfs://nfe/1");

        (, string memory uri, string memory docType,, address uploadedBy) = pharma.batchDocuments(batchId, 0);
        assertEq(uri, "ipfs://nfe/1");
        assertEq(docType, "NFE");
        assertEq(uploadedBy, producer);
    }

    function testAttachFiscalDocValidationReverts() public {
        uint256 batchId = _mintBatchAs(producer, "GTIN-NFE-VAL", 100, 20);

        vm.prank(producer);
        vm.expectRevert("Hash obrigatorio");
        pharma.attachFiscalDoc(batchId, bytes32(0), "ipfs://nfe/ok");

        vm.prank(producer);
        vm.expectRevert("URI obrigatoria");
        pharma.attachFiscalDoc(batchId, keccak256("nfe-ok"), "");
    }

    function testAttachTransportDocOnlyLogistics() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-CTE", 100, 15);

        vm.prank(outsider);
        vm.expectRevert();
        pharma.attachTransportDoc(batchId, keccak256("cte"), "ipfs://cte/1");

        vm.prank(logistics);
        pharma.attachTransportDoc(batchId, keccak256("cte"), "ipfs://cte/1");

        (, string memory uri, string memory docType,, address uploadedBy) = pharma.batchDocuments(batchId, 0);
        assertEq(uri, "ipfs://cte/1");
        assertEq(docType, "CTE");
        assertEq(uploadedBy, logistics);
    }

    function testAttachTransportDocValidationReverts() public {
        uint256 batchId = _mintBatchAs(logistics, "GTIN-CTE-VAL", 100, 20);

        vm.prank(logistics);
        vm.expectRevert("Hash obrigatorio");
        pharma.attachTransportDoc(batchId, bytes32(0), "ipfs://cte/ok");

        vm.prank(logistics);
        vm.expectRevert("URI obrigatoria");
        pharma.attachTransportDoc(batchId, keccak256("cte-ok"), "");
    }

    function testUpdateActorLicenseOnlyOracle() public {
        vm.prank(outsider);
        vm.expectRevert();
        pharma.updateActorLicense(producer, true, "X");

        vm.prank(oracle);
        pharma.updateActorLicense(producer, true, "ANVISA-123");

        (bool isValid,, string memory licenseRef) = pharma.actorLicenses(producer);
        assertTrue(isValid);
        assertEq(licenseRef, "ANVISA-123");
    }

    function testUpdateActorLicenseValidationReverts() public {
        vm.prank(oracle);
        vm.expectRevert("Actor invalido");
        pharma.updateActorLicense(address(0), true, "INVALID");
    }

    function testSetURIValidationReverts() public {
        vm.expectRevert("URI invalida");
        pharma.setURI("");
    }

    function testSupportsInterfaceCoverage() public view {
        assertTrue(pharma.supportsInterface(0x01ffc9a7));
        assertTrue(pharma.supportsInterface(0xd9b67a26));
        assertTrue(pharma.supportsInterface(0x7965db0b));
        assertFalse(pharma.supportsInterface(0xffffffff));
    }
}
