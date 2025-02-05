// SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();

        // deployer returns dsc and engine
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config
            .activeNetworkConfig();

        // mint user
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }
    /**
     *CONSTRUCTOR TESTS
     */

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*
     * PRICE TESTS
     */
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedUsdAmount = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedUsdAmount, actualWeth);
    }

    /**
     * TEST for deposit collateral functions
     */

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    function testEventIsEmitedWhenCollateralIsDeposited() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testBalanceIncreasesAfterDeposit() public {
        uint256 initialBalance = ERC20Mock(weth).balanceOf(USER);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 finalBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(finalBalance, initialBalance - AMOUNT_COLLATERAL);
    }

    /**
     * TEST for minting DSC functions
     */

    function testRevertsIfAmountDscIsZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(this), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testIfDscIsMinted() public depositedCollateral {
        uint256 dscToMint = 5 ether;
        uint256 initialBalance = dsc.balanceOf(USER);
        vm.startPrank(USER);
        engine.mintDsc(dscToMint);
        vm.stopPrank();
        uint256 finalBalance = dsc.balanceOf(USER);
        assertEq(initialBalance + dscToMint, finalBalance);
    }

    function testEventIsEmitedWhenMinted() public depositedCollateral {
        uint256 dscToMint = 5 ether;
        vm.startPrank(USER);
        vm.expectEmit(true, true, false, false);
        emit DSCEngine.DscMinted(USER, dscToMint);
        engine.mintDsc(dscToMint);
        vm.stopPrank();
    }

    function testDscBalanceIncreasesAfterMinting() public depositedCollateral {
        uint256 initialDsc = dsc.balanceOf(USER);
        uint256 dscToMint = 5 ether;
        vm.startPrank(USER);
        engine.mintDsc(dscToMint);
        vm.stopPrank();
        uint256 finalDsc = dsc.balanceOf(USER);
        assertEq(finalDsc, initialDsc + dscToMint);
    }

    /**
     * TEST for redeeming collateral functions
     */

    function testRevertIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCannotRedeemMoreThanDeposited() public depositedCollateral {
        uint256 amountToRedeem = 50 ether;
        vm.startPrank(USER);
        vm.expectRevert("Insufficient collateral");
        engine.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    // function testEventIsEmitedWhenCollateralIsRedeem()
    //     public
    //     depositedCollateral
    // {
    //     uint256 amountCollateral = 5 ether;
    //     vm.startPrank(USER);
    //     vm.expectEmit(true, true, false, false);
    //     emit DSCEngine.CollatralRedeemed(USER, USER, weth, amountCollateral);
    //     engine.redeemCollateral(weth, amountCollateral);
    //     vm.stopPrank();
    // }
}
// DSCEngine:
// 36 36 20 35
