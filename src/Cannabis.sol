// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

/**
 * @title PharmaChainERP
 * @dev Contrato Enterprise para rastreabilidade farmacêutica (GMP, GACP, GDP).
 */
contract PharmaChainERP is
    Initializable,
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _batchIdCounter;
    CountersUpgradeable.Counter private _shipmentIdCounter;

    // --- 1. RBAC ---
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant PRODUCTION_ROLE = keccak256("PRODUCTION_ROLE");
    bytes32 public constant QUALITY_ROLE = keccak256("QUALITY_ROLE");
    bytes32 public constant LOGISTICS_ROLE = keccak256("LOGISTICS_ROLE");

    // --- 2. Status do lote ---
    enum BatchStatus {
        IN_PRODUCTION,
        QUARANTINE,
        RELEASED,
        IN_TRANSIT,
        DELIVERED,
        REJECTED,
        RECALL
    }

    // --- 3. Estruturas ---
    struct Document {
        bytes32 docHash;
        string docUri;
        string docType;
        uint256 timestamp;
        address uploadedBy;
    }

    struct Shipment {
        uint256 shipmentId;
        address dispatcher;
        address carrier;
        address destination;
        uint256 qtyShipped;
        uint256 qtyReceived;
        uint256 qtyLost;
        uint256 dispatchedAt;
        uint256 receivedAt;
        bool isCompleted;
        string lossReason;
    }

    struct BatchInfo {
        string gtin;
        uint256 mfgDate;
        uint256 expDate;
        uint256 productionQty;
        BatchStatus status;
        string recallReason;
    }

    struct ActorLicense {
        bool isValid;
        uint256 updatedAt;
        string licenseRef;
    }

    // --- 4. Storage ---
    mapping(uint256 => bool) private _batchExists;
    mapping(uint256 => BatchInfo) public batches;
    mapping(uint256 => Document[]) public batchDocuments;

    mapping(uint256 => mapping(uint256 => Shipment)) private _batchShipments;
    mapping(uint256 => uint256[]) private _batchShipmentIds;
    mapping(uint256 => uint256) public activeShipmentIdByBatch;

    mapping(address => ActorLicense) public actorLicenses;
    bool public licensingEnforced;

    // --- 5. Eventos ---
    event BatchMinted(uint256 indexed batchId, string gtin, uint256 qty, address indexed actor);
    event StatusChanged(uint256 indexed batchId, BatchStatus oldStatus, BatchStatus newStatus, address indexed actor, string reason);
    event DocumentAttached(uint256 indexed batchId, string docType, bytes32 docHash);

    event ShipmentDispatched(
        uint256 indexed batchId,
        uint256 indexed shipmentId,
        address indexed carrier,
        address dispatcher,
        address destination,
        uint256 qty
    );

    event ShipmentReceived(uint256 indexed batchId, uint256 indexed shipmentId, uint256 qtyReceived, uint256 qtyLost);
    event CriticalDiscrepancy(uint256 indexed batchId, uint256 indexed shipmentId, string message);

    event BatchRejected(uint256 indexed batchId, string reason, address indexed actor);
    event ActorLicenseUpdated(address indexed actor, bool isValid, string licenseRef, address indexed oracle);
    event LicensingEnforcementUpdated(bool enabled, address indexed actor);

    modifier onlyExistingBatch(uint256 batchId) {
        require(_batchExists[batchId], "Lote inexistente");
        _;
    }

    modifier onlyLicensedIfRequired() {
        if (licensingEnforced && !hasRole(ADMIN_ROLE, msg.sender)) {
            require(actorLicenses[msg.sender].isValid, "Licenca inativa");
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory uri) public initializer {
        __ERC1155_init(uri);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ORACLE_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PRODUCTION_ROLE, ADMIN_ROLE);
        _setRoleAdmin(QUALITY_ROLE, ADMIN_ROLE);
        _setRoleAdmin(LOGISTICS_ROLE, ADMIN_ROLE);
    }

    // --- 6. Produção ---
    function mintBatch(
        string memory _gtin,
        uint256 _qty,
        uint256 _expDateInDays
    ) external onlyRole(PRODUCTION_ROLE) onlyLicensedIfRequired whenNotPaused nonReentrant {
        require(bytes(_gtin).length > 0, "GTIN obrigatorio");
        require(_qty > 0, "Quantidade invalida");
        require(_expDateInDays > 0, "Validade invalida");

        _batchIdCounter.increment();
        uint256 newBatchId = _batchIdCounter.current();

        _batchExists[newBatchId] = true;
        batches[newBatchId] = BatchInfo({
            gtin: _gtin,
            mfgDate: block.timestamp,
            expDate: block.timestamp + (_expDateInDays * 1 days),
            productionQty: _qty,
            status: BatchStatus.IN_PRODUCTION,
            recallReason: ""
        });

        _mint(msg.sender, newBatchId, _qty, "");

        emit BatchMinted(newBatchId, _gtin, _qty, msg.sender);
    }

    // --- 7. Qualidade e Compliance ---
    function releaseBatch(
        uint256 batchId,
        bytes32 _coaHash,
        string memory _coaUri
    ) external onlyRole(QUALITY_ROLE) onlyLicensedIfRequired whenNotPaused onlyExistingBatch(batchId) {
        require(
            batches[batchId].status == BatchStatus.IN_PRODUCTION ||
                batches[batchId].status == BatchStatus.QUARANTINE,
            "Status invalido"
        );
        require(_coaHash != bytes32(0), "Hash COA obrigatorio");
        require(bytes(_coaUri).length > 0, "URI COA obrigatoria");

        _attachDocument(batchId, _coaHash, _coaUri, "COA");
        _changeStatus(batchId, BatchStatus.RELEASED, "Lote aprovado pelo Controle de Qualidade");
    }

    function rejectBatch(
        uint256 batchId,
        string memory reason,
        bytes32 evidenceHash,
        string memory evidenceUri
    ) external onlyRole(QUALITY_ROLE) onlyLicensedIfRequired whenNotPaused onlyExistingBatch(batchId) {
        require(bytes(reason).length > 0, "Motivo obrigatorio");
        require(
            batches[batchId].status == BatchStatus.IN_PRODUCTION ||
                batches[batchId].status == BatchStatus.QUARANTINE,
            "Status invalido"
        );

        if (evidenceHash != bytes32(0) || bytes(evidenceUri).length > 0) {
            require(evidenceHash != bytes32(0), "Hash evidencia obrigatorio");
            require(bytes(evidenceUri).length > 0, "URI evidencia obrigatoria");
            _attachDocument(batchId, evidenceHash, evidenceUri, "NCR");
        }

        _changeStatus(batchId, BatchStatus.REJECTED, reason);
        emit BatchRejected(batchId, reason, msg.sender);
    }

    function executeRecall(
        uint256 batchId,
        string memory _reason
    ) external onlyRole(QUALITY_ROLE) onlyLicensedIfRequired onlyExistingBatch(batchId) {
        require(bytes(_reason).length > 0, "Motivo obrigatorio");

        batches[batchId].recallReason = _reason;
        _changeStatus(batchId, BatchStatus.RECALL, _reason);
    }

    // --- 8. Documentos ERP/Fiscal ---
    function attachFiscalDoc(
        uint256 batchId,
        bytes32 _hash,
        string memory _uri
    ) external whenNotPaused onlyExistingBatch(batchId) {
        require(
            hasRole(PRODUCTION_ROLE, msg.sender) || hasRole(LOGISTICS_ROLE, msg.sender),
            "Acesso negado"
        );
        require(_hash != bytes32(0), "Hash obrigatorio");
        require(bytes(_uri).length > 0, "URI obrigatoria");

        _attachDocument(batchId, _hash, _uri, "NFE");
    }

    function attachTransportDoc(
        uint256 batchId,
        bytes32 _hash,
        string memory _uri
    ) external onlyRole(LOGISTICS_ROLE) onlyLicensedIfRequired whenNotPaused onlyExistingBatch(batchId) {
        require(_hash != bytes32(0), "Hash obrigatorio");
        require(bytes(_uri).length > 0, "URI obrigatoria");

        _attachDocument(batchId, _hash, _uri, "CTE");
    }

    // --- 9. Logistica e distribuicao ---
    function shipBatch(
        uint256 batchId,
        address _carrier,
        address _destination,
        uint256 _qty
    ) external onlyRole(LOGISTICS_ROLE) onlyLicensedIfRequired whenNotPaused nonReentrant onlyExistingBatch(batchId) {
        require(_carrier != address(0), "Carrier invalido");
        require(_destination != address(0), "Destino invalido");
        require(_qty > 0, "Quantidade invalida");
        require(activeShipmentIdByBatch[batchId] == 0, "Ja existe remessa ativa");
        require(hasRole(LOGISTICS_ROLE, _destination), "Destino sem LOGISTICS_ROLE");

        BatchStatus currentStatus = batches[batchId].status;
        require(
            currentStatus == BatchStatus.RELEASED || currentStatus == BatchStatus.DELIVERED,
            "Lote nao liberado"
        );
        require(block.timestamp < batches[batchId].expDate, "ERRO: Lote vencido");
        require(balanceOf(msg.sender, batchId) >= _qty, "Saldo insuficiente");

        _performManagedTransfer(msg.sender, _carrier, batchId, _qty);

        _shipmentIdCounter.increment();
        uint256 shipmentId = _shipmentIdCounter.current();

        _batchShipments[batchId][shipmentId] = Shipment({
            shipmentId: shipmentId,
            dispatcher: msg.sender,
            carrier: _carrier,
            destination: _destination,
            qtyShipped: _qty,
            qtyReceived: 0,
            qtyLost: 0,
            dispatchedAt: block.timestamp,
            receivedAt: 0,
            isCompleted: false,
            lossReason: ""
        });

        _batchShipmentIds[batchId].push(shipmentId);
        activeShipmentIdByBatch[batchId] = shipmentId;

        _changeStatus(batchId, BatchStatus.IN_TRANSIT, "Despachado para transportadora");
        emit ShipmentDispatched(batchId, shipmentId, _carrier, msg.sender, _destination, _qty);
    }

    function receiveShipment(
        uint256 batchId,
        uint256 _qtyReceived,
        uint256 _qtyLost,
        string memory _lossReason
    ) external onlyRole(LOGISTICS_ROLE) onlyLicensedIfRequired whenNotPaused nonReentrant onlyExistingBatch(batchId) {
        uint256 shipmentId = activeShipmentIdByBatch[batchId];
        require(shipmentId != 0, "Nao ha remessa ativa");

        Shipment storage shipment = _batchShipments[batchId][shipmentId];

        require(msg.sender == shipment.destination, "Apenas o destino correto pode receber");
        require(batches[batchId].status == BatchStatus.IN_TRANSIT, "Carga nao esta em transito");
        require(!shipment.isCompleted, "Entrega ja finalizada");
        require(shipment.qtyShipped >= (_qtyReceived + _qtyLost), "Quantidades invalidas");

        if (_qtyLost > 0) {
            require(bytes(_lossReason).length > 0, "Motivo da perda obrigatorio");
        }

        shipment.qtyReceived = _qtyReceived;
        shipment.qtyLost = _qtyLost;
        shipment.receivedAt = block.timestamp;
        shipment.isCompleted = true;
        shipment.lossReason = _lossReason;

        activeShipmentIdByBatch[batchId] = 0;

        if (shipment.qtyShipped != (_qtyReceived + _qtyLost)) {
            emit CriticalDiscrepancy(batchId, shipmentId, "Quantidade despachada difere de recebida + perdas");
            _changeStatus(batchId, BatchStatus.QUARANTINE, "Discrepancia logistica - Investigacao iniciada");
        } else {
            if (_qtyReceived > 0) {
                _performManagedTransfer(shipment.carrier, msg.sender, batchId, _qtyReceived);
            }

            if (_qtyLost > 0) {
                _burn(shipment.carrier, batchId, _qtyLost);
                _attachDocument(batchId, keccak256(abi.encodePacked(_lossReason)), "", "LOSS_REPORT");
            }

            _changeStatus(batchId, BatchStatus.DELIVERED, "Entrega concluida");
        }

        emit ShipmentReceived(batchId, shipmentId, _qtyReceived, _qtyLost);
    }

    // --- 10. Funcoes administrativas e consultas ---
    function updateActorLicense(
        address actor,
        bool isValid,
        string calldata licenseRef
    ) external onlyRole(ORACLE_ROLE) whenNotPaused {
        require(actor != address(0), "Actor invalido");

        actorLicenses[actor] = ActorLicense({isValid: isValid, updatedAt: block.timestamp, licenseRef: licenseRef});
        emit ActorLicenseUpdated(actor, isValid, licenseRef, msg.sender);
    }

    function setLicensingEnforcement(bool enabled) external onlyRole(ADMIN_ROLE) {
        licensingEnforced = enabled;
        emit LicensingEnforcementUpdated(enabled, msg.sender);
    }

    function setURI(string calldata newUri) external onlyRole(ADMIN_ROLE) {
        require(bytes(newUri).length > 0, "URI invalida");
        _setURI(newUri);
    }

    function getShipment(
        uint256 batchId,
        uint256 shipmentId
    ) external view onlyExistingBatch(batchId) returns (Shipment memory) {
        Shipment memory shipment = _batchShipments[batchId][shipmentId];
        require(shipment.shipmentId != 0, "Remessa inexistente");
        return shipment;
    }

    function getShipmentIds(uint256 batchId) external view onlyExistingBatch(batchId) returns (uint256[] memory) {
        return _batchShipmentIds[batchId];
    }

    function _attachDocument(
        uint256 batchId,
        bytes32 _hash,
        string memory _uri,
        string memory _type
    ) internal onlyExistingBatch(batchId) {
        require(_hash != bytes32(0), "Hash obrigatorio");
        require(bytes(_type).length > 0, "Tipo obrigatorio");

        if (keccak256(bytes(_type)) != keccak256(bytes("LOSS_REPORT"))) {
            require(bytes(_uri).length > 0, "URI obrigatoria");
        }

        batchDocuments[batchId].push(
            Document({
                docHash: _hash,
                docUri: _uri,
                docType: _type,
                timestamp: block.timestamp,
                uploadedBy: msg.sender
            })
        );

        emit DocumentAttached(batchId, _type, _hash);
    }

    function _performManagedTransfer(address from, address to, uint256 id, uint256 amount) internal {
        _safeTransferFrom(from, to, id, amount, "");
    }

    function _changeStatus(uint256 batchId, BatchStatus newStatus, string memory reason) internal {
        BatchStatus oldStatus = batches[batchId].status;
        require(oldStatus != newStatus, "Status ja definido");
        require(_isValidTransition(oldStatus, newStatus), "Transicao de status invalida");

        batches[batchId].status = newStatus;
        emit StatusChanged(batchId, oldStatus, newStatus, msg.sender, reason);
    }

    function _isValidTransition(BatchStatus from, BatchStatus to) internal pure returns (bool) {
        if (from == BatchStatus.IN_PRODUCTION) {
            return to == BatchStatus.QUARANTINE || to == BatchStatus.RELEASED || to == BatchStatus.REJECTED || to == BatchStatus.RECALL;
        }
        if (from == BatchStatus.QUARANTINE) {
            return to == BatchStatus.RELEASED || to == BatchStatus.REJECTED || to == BatchStatus.RECALL;
        }
        if (from == BatchStatus.RELEASED) {
            return to == BatchStatus.IN_TRANSIT || to == BatchStatus.RECALL;
        }
        if (from == BatchStatus.IN_TRANSIT) {
            return to == BatchStatus.DELIVERED || to == BatchStatus.QUARANTINE || to == BatchStatus.RECALL;
        }
        if (from == BatchStatus.DELIVERED) {
            return to == BatchStatus.IN_TRANSIT || to == BatchStatus.RECALL;
        }
        if (from == BatchStatus.REJECTED) {
            return to == BatchStatus.RECALL;
        }

        return false;
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        bool isMint = from == address(0);

        if (!isMint) {
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 id = ids[i];
                require(_batchExists[id], "Lote inexistente");
                require(batches[id].status != BatchStatus.RECALL, "BLOQUEIO: Lote em RECALL");
                require(batches[id].status != BatchStatus.REJECTED, "BLOQUEIO: Lote REPROVADO");
                require(batches[id].status != BatchStatus.QUARANTINE, "BLOQUEIO: Lote em QUARENTENA");
                require(block.timestamp < batches[id].expDate, "BLOQUEIO: Lote VENCIDO");
            }
        }
    }

    function safeTransferFrom(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure override {
        revert("Transferencia direta bloqueada");
    }

    function safeBatchTransferFrom(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure override {
        revert("Transferencia direta bloqueada");
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    function pauseContract() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    uint256[42] private __gap;
}
