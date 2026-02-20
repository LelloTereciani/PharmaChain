// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Cannabis.sol";

abstract contract PharmaChainERPBase is Test {
    PharmaChainERP internal pharma;
    PharmaChainERP internal implementation;

    address internal producer = makeAddr("producer");
    address internal quality = makeAddr("quality");
    address internal logistics = makeAddr("logistics");
    address internal carrier = makeAddr("carrier");
    address internal destination = makeAddr("destination");
    address internal oracle = makeAddr("oracle");
    address internal outsider = makeAddr("outsider");

    uint256 internal nextExpectedBatchId;

    string internal constant BASE_URI = "ipfs://pharma/{id}.json";

    function setUp() public virtual {
        implementation = new PharmaChainERP();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(PharmaChainERP.initialize, (BASE_URI))
        );

        pharma = PharmaChainERP(address(proxy));
        nextExpectedBatchId = 1;

        pharma.grantRole(pharma.PRODUCTION_ROLE(), producer);
        pharma.grantRole(pharma.PRODUCTION_ROLE(), logistics);

        pharma.grantRole(pharma.QUALITY_ROLE(), quality);

        pharma.grantRole(pharma.LOGISTICS_ROLE(), logistics);
        pharma.grantRole(pharma.LOGISTICS_ROLE(), destination);

        pharma.grantRole(pharma.ORACLE_ROLE(), oracle);
    }

    function _mintBatchAs(
        address actor,
        string memory gtin,
        uint256 qty,
        uint256 validityDays
    ) internal returns (uint256 batchId) {
        batchId = nextExpectedBatchId;
        nextExpectedBatchId++;

        vm.prank(actor);
        pharma.mintBatch(gtin, qty, validityDays);
    }

    function _releasedBatch(uint256 qty) internal returns (uint256 batchId) {
        batchId = _mintBatchAs(logistics, "GTIN-REL", qty, 30);

        vm.prank(quality);
        pharma.releaseBatch(batchId, keccak256("coa"), "ipfs://coa/rel");
    }

    function _status(uint256 batchId) internal view returns (PharmaChainERP.BatchStatus) {
        (, , , , PharmaChainERP.BatchStatus status, ) = pharma.batches(batchId);
        return status;
    }

    function _expDate(uint256 batchId) internal view returns (uint256) {
        (, , uint256 expDate, , , ) = pharma.batches(batchId);
        return expDate;
    }

    function _callAndMeasure(address caller, bytes memory data) internal returns (uint256 gasUsed) {
        uint256 gasBefore = gasleft();

        vm.prank(caller);
        (bool ok, bytes memory result) = address(pharma).call(data);
        if (!ok) {
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            revert("Low-level call failed");
        }

        gasUsed = gasBefore - gasleft();
    }
}

contract PharmaChainERPHarness is PharmaChainERP {
    function exposedSetBatchStatus(uint256 batchId, BatchStatus status) external {
        batches[batchId].status = status;
    }

    function exposedChangeStatus(uint256 batchId, BatchStatus newStatus, string calldata reason) external {
        _changeStatus(batchId, newStatus, reason);
    }
}
