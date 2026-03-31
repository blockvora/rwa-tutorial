// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IIdentity} from "../interfaces/IIdentity.sol";

/**
 * @title MockIdentity
 * @notice Simplified identity contract for testing and tutorial purposes
 * @dev In production, use full ONCHAINID implementation
 * 
 * This mock allows:
 * - Adding claims manually (for testing)
 * - Checking key purposes
 * - Simulating a real identity contract without full complexity
 */
contract MockIdentity is IIdentity {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The wallet address this identity represents
    address public owner;

    /// @notice Stored claims (claimId => Claim)
    mapping(bytes32 => Claim) private _claims;

    /// @notice Keys with specific purposes (key => purpose => exists)
    mapping(bytes32 => mapping(uint256 => bool)) private _keys;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new mock identity
     * @param _owner The wallet address this identity represents
     */
    constructor(address _owner) {
        owner = _owner;

        // Add owner's address as a management key (purpose 1)
        bytes32 key = keccak256(abi.encode(_owner));
        _keys[key][1] = true; // 1 = MANAGEMENT purpose
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get a claim from this identity
     * @param claimId The claim identifier
     * @return topic The claim topic
     * @return scheme The signature scheme
     * @return issuer The claim issuer
     * @return signature The issuer's signature
     * @return data The claim data
     * @return uri Additional claim information URI
     */
    function getClaim(bytes32 claimId)
        external
        view
        override
        returns (uint256 topic, uint256 scheme, address issuer, bytes memory signature, bytes memory data, string memory uri)
    {
        Claim memory claim = _claims[claimId];
        return (claim.topic, claim.scheme, claim.issuer, claim.signature, claim.data, claim.uri);
    }

    /**
     * @notice Add a claim to this identity (for testing)
     * @param topic The claim topic (e.g., 1 = KYC)
     * @param scheme The signature scheme (e.g., 1 = ECDSA)
     * @param issuer The claim issuer address
     * @param signature The issuer's signature
     * @param data The claim data
     * @param uri Additional information URI
     * 
     * @dev In production, only the identity owner or authorized keys can add claims
     * @dev For simplicity, this mock allows anyone to add claims
     */
    function addClaim(
        uint256 topic,
        uint256 scheme,
        address issuer,
        bytes memory signature,
        bytes memory data,
        string memory uri
    ) external returns (bytes32 claimId) {
        claimId = keccak256(abi.encode(issuer, topic));

        _claims[claimId] = Claim({topic: topic, scheme: scheme, issuer: issuer, signature: signature, data: data, uri: uri});

        return claimId;
    }

    /**
     * @notice Remove a claim from this identity (for testing)
     * @param claimId The claim to remove
     */
    function removeClaim(bytes32 claimId) external {
        delete _claims[claimId];
    }

    /*//////////////////////////////////////////////////////////////
                            KEY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a key has a specific purpose
     * @param key The key to check
     * @param purpose The purpose (1 = MANAGEMENT, 2 = ACTION, 3 = CLAIM, 4 = ENCRYPTION)
     * @return exists True if the key has this purpose
     */
    function keyHasPurpose(bytes32 key, uint256 purpose) external view override returns (bool) {
        return _keys[key][purpose];
    }

    /**
     * @notice Add a key with a specific purpose (for testing)
     * @param key The key to add
     * @param purpose The purpose to grant
     */
    function addKey(bytes32 key, uint256 purpose) external {
        _keys[key][purpose] = true;
    }
}
