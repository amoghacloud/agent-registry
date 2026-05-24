// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title  AgentRegistry
/// @notice Permanent onchain identity registry for autonomous AI agents
/// @dev    Pure registry. No ERC721. No external dependencies.
///         EVM target: paris (no PUSH0, full L2 compatibility)

contract AgentRegistry {

    // ─────────────────────────────────────────
    // CUSTOM ERRORS
    // ─────────────────────────────────────────

    error NotOwner();
    error NotController();
    error AgentNotFound();
    error Locked();
    error ExactFeeRequired();
    error NameRequired();
    error NameTooLong();
    error MetadataURIRequired();
    error MetadataHashRequired();
    error InvalidAddress();
    error AlreadyController();
    error AlreadyInactive();
    error AlreadyActive();
    error AgentNotActive();
    error NothingToWithdraw();
    error WithdrawFailed();
    error InsufficientBalance();
    error MessageTooLong();
    error NoPendingTransfer();
    error ZeroAmount();

    // ─────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────

    address public owner;
    address public pendingOwner;          // two-step ownership

    uint256 public registrationFee = 0.001 ether;
    uint256 public transferFee     = 0.0005 ether;
    uint256 public nextId          = 1;
    uint256 private unlocked       = 1;

    uint256 public totalRegistrations;
    uint256 public totalDonations;
    uint256 public totalFeesCollected;

    mapping(uint256 => Agent)     public agents;
    mapping(address => uint256[]) public controllerAgents;
    mapping(uint256 => uint256)   public agentIndex;
    mapping(address => uint256)   public donorContributions;

    // ─────────────────────────────────────────
    // STRUCTS
    // ─────────────────────────────────────────

    struct Agent {
        uint256 id;
        address controller;
        string  name;
        string  metadataURI;
        bytes32 metadataHash;
        uint256 createdAt;
        bool    active;
    }

    // ─────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────

    event AgentRegistered(
        uint256 indexed id,
        address indexed controller,
        string  name,
        bytes32 metadataHash,
        uint256 timestamp
    );
    event ControllerTransferred(
        uint256 indexed id,
        address indexed oldController,
        address indexed newController,
        uint256 timestamp
    );
    event AgentDeactivated(uint256 indexed id, address indexed controller, uint256 timestamp);
    event AgentReactivated(uint256 indexed id, address indexed controller, uint256 timestamp);
    event MetadataUpdated(uint256 indexed id, string newURI, bytes32 newHash, uint256 timestamp);
    event DonationReceived(address indexed donor, uint256 amount, string message, uint256 timestamp);
    event FeeUpdated(string feeType, uint256 oldFee, uint256 newFee);
    event Withdrawn(address indexed to, uint256 amount, uint256 timestamp);

    // Two-step ownership events
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferCancelled(address indexed currentOwner, address indexed cancelledPending);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    // ─────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyController(uint256 id) {
        if (agents[id].controller != msg.sender) revert NotController();
        _;
    }

    modifier agentExists(uint256 id) {
        if (id == 0 || id >= nextId) revert AgentNotFound();
        _;
    }

    modifier onlyActive(uint256 id) {
        if (!agents[id].active) revert AgentNotActive();
        _;
    }

    modifier nonReentrant() {
        if (unlocked != 1) revert Locked();
        unlocked = 2;
        _;
        unlocked = 1;
    }

    // ─────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─────────────────────────────────────────
    // CORE — REGISTRATION
    // ─────────────────────────────────────────

    /// @notice Register a new AI agent identity
    /// @param  name         Display label — not unique, ID is the identity
    /// @param  metadataURI  IPFS URI pointing to agent metadata JSON
    /// @param  metadataHash keccak256 of metadata JSON for integrity verification
    /// @return id           Permanent immutable agent ID
    function register(
        string  calldata name,
        string  calldata metadataURI,
        bytes32          metadataHash
    ) external payable returns (uint256 id) {
        if (msg.value != registrationFee)      revert ExactFeeRequired();
        if (bytes(name).length == 0)           revert NameRequired();
        if (bytes(name).length > 64)           revert NameTooLong();
        if (bytes(metadataURI).length == 0)    revert MetadataURIRequired();
        if (metadataHash == bytes32(0))        revert MetadataHashRequired();

        id = nextId++;

        agents[id] = Agent({
            id:           id,
            controller:   msg.sender,
            name:         name,
            metadataURI:  metadataURI,
            metadataHash: metadataHash,
            createdAt:    block.timestamp,
            active:       true
        });

        agentIndex[id] = controllerAgents[msg.sender].length;
        controllerAgents[msg.sender].push(id);

        totalRegistrations++;
        totalFeesCollected += msg.value;

        emit AgentRegistered(id, msg.sender, name, metadataHash, block.timestamp);
    }

    // ─────────────────────────────────────────
    // CORE — CONTROLLER MANAGEMENT
    // ─────────────────────────────────────────

    /// @notice Transfer control of an agent — agent must be active
    function transferController(
        uint256 id,
        address newController
    ) external payable agentExists(id) onlyController(id) onlyActive(id) {
        if (msg.value != transferFee)          revert ExactFeeRequired();
        if (newController == address(0))       revert InvalidAddress();
        if (newController == msg.sender)       revert AlreadyController();

        address old = agents[id].controller;
        _removeFromControllerList(old, id);

        agentIndex[id] = controllerAgents[newController].length;
        controllerAgents[newController].push(id);
        agents[id].controller = newController;

        totalFeesCollected += msg.value;

        emit ControllerTransferred(id, old, newController, block.timestamp);
    }

    // ─────────────────────────────────────────
    // CORE — METADATA UPDATE
    // ─────────────────────────────────────────

    /// @notice Update agent metadata — agent must be active
    function updateMetadata(
        uint256 id,
        string  calldata newURI,
        bytes32          newHash
    ) external agentExists(id) onlyController(id) onlyActive(id) {
        if (bytes(newURI).length == 0) revert MetadataURIRequired();
        if (newHash == bytes32(0))     revert MetadataHashRequired();

        agents[id].metadataURI  = newURI;
        agents[id].metadataHash = newHash;

        emit MetadataUpdated(id, newURI, newHash, block.timestamp);
    }

    // ─────────────────────────────────────────
    // CORE — ACTIVATION
    // ─────────────────────────────────────────

    function deactivate(uint256 id)
        external agentExists(id) onlyController(id)
    {
        if (!agents[id].active) revert AlreadyInactive();
        agents[id].active = false;
        emit AgentDeactivated(id, msg.sender, block.timestamp);
    }

    function reactivate(uint256 id)
        external agentExists(id) onlyController(id)
    {
        if (agents[id].active) revert AlreadyActive();
        agents[id].active = true;
        emit AgentReactivated(id, msg.sender, block.timestamp);
    }

    // ─────────────────────────────────────────
    // DONATIONS
    // ─────────────────────────────────────────

    function donate(string calldata message) external payable {
        if (msg.value == 0)                revert ZeroAmount();
        if (bytes(message).length > 280)   revert MessageTooLong();

        totalDonations                 += msg.value;
        donorContributions[msg.sender] += msg.value;

        emit DonationReceived(msg.sender, msg.value, message, block.timestamp);
    }

    // ─────────────────────────────────────────
    // READ
    // ─────────────────────────────────────────

    function getAgent(uint256 id)
        external view agentExists(id)
        returns (Agent memory)
    {
        return agents[id];
    }

    function getControllerAgents(address controller)
        external view
        returns (uint256[] memory)
    {
        return controllerAgents[controller];
    }

    function totalAgents() external view returns (uint256) {
        return nextId - 1;
    }

    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getStats() external view returns (
        uint256 _totalAgents,
        uint256 _totalDonations,
        uint256 _totalFees,
        uint256 _balance
    ) {
        return (
            nextId - 1,
            totalDonations,
            totalFeesCollected,
            address(this).balance
        );
    }

    // ─────────────────────────────────────────
    // ADMIN — FEES
    // ─────────────────────────────────────────

    function setRegistrationFee(uint256 newFee) external onlyOwner {
        emit FeeUpdated("registration", registrationFee, newFee);
        registrationFee = newFee;
    }

    function setTransferFee(uint256 newFee) external onlyOwner {
        emit FeeUpdated("transfer", transferFee, newFee);
        transferFee = newFee;
    }

    // ─────────────────────────────────────────
    // ADMIN — WITHDRAWAL
    // ─────────────────────────────────────────

    function withdraw() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        if (bal == 0) revert NothingToWithdraw();
        (bool ok, ) = owner.call{value: bal}("");
        if (!ok) revert WithdrawFailed();
        emit Withdrawn(owner, bal, block.timestamp);
    }

    function withdrawTo(address payable to, uint256 amount)
        external onlyOwner nonReentrant
    {
        if (to == address(0))                revert InvalidAddress();
        if (amount == 0)                     revert ZeroAmount();
        if (amount > address(this).balance)  revert InsufficientBalance();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert WithdrawFailed();
        emit Withdrawn(to, amount, block.timestamp);
    }

    // ─────────────────────────────────────────
    // ADMIN — TWO-STEP OWNERSHIP
    // ─────────────────────────────────────────

    /// @notice Step 1 — current owner nominates a new owner
    function initiateOwnershipTransfer(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }

    /// @notice Step 2 — pending owner claims ownership
    /// @dev    Only the exact address nominated can call this
    function claimOwnership() external {
        if (msg.sender != pendingOwner) revert NoPendingTransfer();
        address old = owner;
        owner        = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(old, owner);
    }

    /// @notice Cancel a pending ownership transfer
    function cancelOwnershipTransfer() external onlyOwner {
        address cancelled = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferCancelled(owner, cancelled);
    }

    // ─────────────────────────────────────────
    // INTERNAL
    // ─────────────────────────────────────────

    function _removeFromControllerList(address controller, uint256 id) internal {
        uint256[] storage list = controllerAgents[controller];
        uint256          idx   = agentIndex[id];
        uint256          last  = list[list.length - 1];

        list[idx]        = last;
        agentIndex[last] = idx;
        list.pop();

        delete agentIndex[id];
    }

    // ─────────────────────────────────────────
    // SAFETY
    // ─────────────────────────────────────────

    receive() external payable {
        revert("Use donate()");
    }

    fallback() external payable {
        revert("Invalid call");
    }
}