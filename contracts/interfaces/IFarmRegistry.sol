// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IFarmRegistry {
    // Events.
    event FarmRegistered(address indexed farm, address indexed creator, address indexed deployer);
    event FarmDeployerUpdated(address indexed deployer, bool registered);
    event FeeParamsUpdated(address indexed receiver, address indexed token, uint256 amount, uint256 extensionFeePerDay);
    event PrivilegeUpdated(address indexed deployer, bool privilege);

    // Custom Errors.
    error DeployerNotRegistered();
    error FarmAlreadyRegistered();
    error DeployerAlreadyRegistered();
    error InvalidDeployerId();
    error PrivilegeSameAsDesired();
    error InvalidAddress();

    /// @notice constructor
    /// @param _feeReceiver Receiver of the fees.
    /// @param _feeToken The fee token for farm creation.
    /// @param _feeAmount The fee amount to be paid by the creator.
    /// @param _extensionFeePerDay Extension fee per day.
    function initialize(address _feeReceiver, address _feeToken, uint256 _feeAmount, uint256 _extensionFeePerDay)
        external;

    /// @notice Register a farm created by registered Deployer.
    /// @dev Only registered deployer can register a farm.
    /// @param _farm Address of the created farm contract
    /// @param _creator Address of the farm creator.
    function registerFarm(address _farm, address _creator) external;

    /// @notice Register a new farm deployer.
    /// @param  _deployer Address of deployer to be registered.
    /// @dev Only owner can call this function.
    function registerFarmDeployer(address _deployer) external;

    /// @notice Remove an existing deployer from registry.
    /// @param _id ID of the deployer to be removed (0 index based).
    /// @dev Only owner can call this function.
    function removeDeployer(uint16 _id) external;

    /// @notice Function to add/remove privileged User.
    /// @param _user User Address for which privilege is to be updated.
    /// @param _privilege Privilege(bool) whether true or false.
    /// @dev Only callable by the owner.
    function updatePrivilege(address _user, bool _privilege) external;

    /// @notice Update the fee params for registry.
    /// @param _receiver FeeReceiver address.
    /// @param _feeToken Token address for fee.
    /// @param _amount Amount of token to be collected.
    /// @param _extensionFeePerDay Extension fee per day.
    function updateFeeParams(address _receiver, address _feeToken, uint256 _amount, uint256 _extensionFeePerDay)
        external;

    /// @notice Get list of registered deployer.
    /// @return Returns array of registered deployer addresses.
    function getFarmDeployerList() external view returns (address[] memory);

    /// @notice Get list of farms created via registered deployer.
    /// @return Returns array of farm addresses.
    function getFarmList() external view returns (address[] memory);

    /// @notice Get all the fee parameters for creating farm.
    /// @param _user The account creating the farm.
    /// @return Receiver of the fees.
    /// @return Token in which fee is to be paid.
    /// @return Amount of fees to be paid for creation of farm.
    /// @return Extension fee per day in case of extending a farm.
    /// @dev It returns fee amount and extension fee as 0 if _user is privileged.
    function getFeeParams(address _user) external view returns (address, address, uint256, uint256);

    // --------------------- Public Variable(functions) ---------------------
    // Global Params.
    function feeReceiver() external view returns (address);
    function feeToken() external view returns (address);
    function feeAmount() external view returns (uint256);
    function extensionFeePerDay() external view returns (uint256);

    function farmRegistered(address) external view returns (bool);
    function deployerRegistered(address) external view returns (bool);
    function isPrivilegedUser(address) external view returns (bool);
}
