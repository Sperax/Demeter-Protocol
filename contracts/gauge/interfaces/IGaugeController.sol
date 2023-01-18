pragma solidity 0.8.10;

interface IGaugeController {
    /// @notice gets the number of gauge registered with the controller.
    function nGauges() external returns (uint256);

    // @notice Get gauge weight normalized to 1e18 and also fill all the unfilled
    //         values for type and gauge records
    // @dev Any address can call, however nothing is recorded if the values are filled already
    // @param _gAddr Gauge address
    // @param _time Relative weight at the specified timestamp in the past or present
    // @return Value of relative weight normalized to 1e18
    function gaugeRelativeWeightWrite(address _gAddr, uint256 _time)
        external
        returns (uint256);

    function gaugeRelativeWeightWrite(address _gAddr)
        external
        returns (uint256);

    // @notice Get gauge type for address
    // @param _gAddr Gauge address
    // @return Gauge type id
    function gaugeType(address _gAddr) external view returns (uint128);

    // @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18
    //         (e.g. 1.0 == 1e18). Inflation which will be received by it is
    //         inflation_rate * relative_weight / 1e18
    // @param _gAddr Gauge address
    // @param _time Relative weight at the specified timestamp in the past or present
    // @return Value of relative weight normalized to 1e18
    function gaugeRelativeWeight(address _gAddr, uint256 _time)
        external
        view
        returns (uint256);

    function gaugeRelativeWeight(address _gAddr)
        external
        view
        returns (uint256);

    // @notice Get current gauge weight
    // @param _gAddr Gauge address
    // @return Gauge weight
    function getGaugeWeight(address _gAddr) external view returns (uint256);
}
