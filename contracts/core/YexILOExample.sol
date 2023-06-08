// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import "../libraries/ERC20.sol";
import "../libraries/AutomationCompatibleInterface.sol";
import "../libraries/Math.sol";
import "../libraries/Ownable.sol";
import "../libraries/Console.sol";

contract ERC20WithFaucet is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}

    mapping(address => bool) public faucetedList;

    function faucet() public {
        require(!faucetedList[msg.sender], "fauceted");
        faucetedList[msg.sender] = true;
        _mint(msg.sender, 10 ** decimals());
    }
}

contract ERC20Mintable is ERC20, Ownable {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

contract YexILOExample is
    ERC20("YexILOExampleLP", "ILOTestLP"),
    AutomationCompatibleInterface
{
    // Constant K value pool
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;

    // use tokenA to subscribe tokenB
    mapping(address => uint256) public tokenA_deposit;
    address[] public tokenA_deposit_address;
    address public tokenB_provider;
    uint256 deposited_TokenA;
    uint256 deposited_TokenB;

    uint256 start_time = block.timestamp;
    uint256 public end_time;
    bool public isInitialized = false;

    constructor(uint256 raising_cycle) {
        // --------------- init token ---------------
        // init test token A
        // in demo, user can use test token A to subscribe token B
        ERC20WithFaucet tokenA_ = new ERC20WithFaucet("TestTokenA", "TTA");
        tokenA_.faucet();
        // init test token B and transfer some test token B to the provider
        // in demo, provider will use token B to raising fund
        tokenB_provider = msg.sender;
        ERC20Mintable tokenB_ = new ERC20Mintable("TestTokenB", "TTB");
        // unchecked {
        uint256 amount = 1000000 * (10 ** tokenB_.decimals()); // mint 100000 tokenB
        tokenB_.mint(msg.sender, amount);
        // }
        // after get token, provider and user both use `deposit` function to deposit token
        // --------------- init token ---------------

        tokenA = IERC20(address(tokenA_));
        tokenB = IERC20(address(tokenB_));

        end_time = start_time + raising_cycle;
    }

    function mint(address to, uint256 amount) private {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) private {
        _burn(from, amount);
    }

    // Modifier to check token allowance
    modifier checkAllowance(uint256 amountA, uint256 amountB) {
        require(
            tokenA.allowance(msg.sender, address(this)) >= amountA,
            "Not allowance tokenA"
        );
        require(
            tokenB.allowance(msg.sender, address(this)) >= amountB,
            "Not allowance tokenB"
        );
        _;
    }

    function deposit(
        uint256 amountA,
        uint256 amountB
    ) external checkAllowance(amountA, amountB) {
        require(
            amountA > 0 || amountB > 0,
            "deposit: INSUFFICIENT_INPUT_AMOUNT"
        );
        require(block.timestamp < end_time, "deposit: raising time is over");

        if (amountA > 0) {
            tokenA.transferFrom(msg.sender, address(this), amountA);

            if (tokenA_deposit[msg.sender] == 0) {
                tokenA_deposit_address.push(address(msg.sender));
            }

            tokenA_deposit[msg.sender] = tokenA_deposit[msg.sender] + amountA;

            deposited_TokenA = deposited_TokenA + amountA;
        }
        if (amountB > 0) {
            tokenB.transferFrom(msg.sender, address(this), amountB);
            deposited_TokenB = deposited_TokenB + amountB;
        }
        // emit Deposit(msg.sender, batchid, amountA, amountB);
    }

    // add liquidity, support add single side liquidity
    function addLiquidity(
        uint256 amountA,
        uint256 amountB
    ) external checkAllowance(amountA, amountB) {
        require(
            amountA > 0 || amountB > 0,
            "addLiquidity: INSUFFICIENT_INPUT_AMOUNT"
        );
        require(isInitialized, "pool has not been initialized"); // do we need this variable?
        uint256 lp_supply = totalSupply();
        require(lp_supply > 0, "pool has not been initialized");
        uint256 amountLP = 0;

        if (amountA > 0) {
            tokenA.transferFrom(msg.sender, address(this), amountA);
            amountLP +=
                (lp_supply * Math.sqrt((amountA + reserveA) * reserveA)) /
                reserveA -
                lp_supply;
            lp_supply += amountLP;
            reserveA += amountA;
        }
        if (amountB > 0) {
            tokenB.transferFrom(msg.sender, address(this), amountB);
            amountLP +=
                (lp_supply * Math.sqrt((amountB + reserveB) * reserveB)) /
                reserveB -
                lp_supply;
            // lp_supply += amountLP; // do not used, can comment out
            reserveB += amountB;
        }
        mint(msg.sender, amountLP);
    }

    // Modifier to check token allowance
    modifier checkLPAllowance(uint256 amountLPB) {
        require(
            allowance(msg.sender, address(this)) >= amountLPB,
            "Not allowance LP token"
        );
        _;
    }

    // remove liquidity
    function removeLiquidity(
        uint256 amountLP,
        int withdraw_A_or_B_or_Both
    ) external checkLPAllowance(amountLP) {
        require(amountLP > 0, "removeLiquidity: INSUFFICIENT_INPUT_AMOUNT");
        uint256 lp_supply = totalSupply();
        require(lp_supply > 0, "pool has not been initialized");
        require(
            0 <= withdraw_A_or_B_or_Both && withdraw_A_or_B_or_Both <= 2,
            "withdraw_A_or_B_or_Both should be 0, 1 or 2"
        );

        burn(msg.sender, amountLP);
        uint256 _reserveA = reserveA;
        uint256 _reserveB = reserveB;

        if (withdraw_A_or_B_or_Both == 0) {
            tokenA.transfer(msg.sender, (amountLP * _reserveA) / lp_supply);
            tokenB.transfer(msg.sender, (amountLP * _reserveB) / lp_supply);
        } else if (withdraw_A_or_B_or_Both == 1) {
            uint256 amount = _reserveA -
                ((_reserveA *
                    ((lp_supply - amountLP) * (lp_supply - amountLP))) /
                    lp_supply /
                    lp_supply);
            tokenA.transfer(msg.sender, amount);
        } else if (withdraw_A_or_B_or_Both == 2) {
            uint256 amount = _reserveB -
                ((_reserveB *
                    ((lp_supply - amountLP) * (lp_supply - amountLP))) /
                    lp_supply /
                    lp_supply);
            tokenB.transfer(msg.sender, amount);
        }
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = block.timestamp > end_time;
        performData = "";
    }

    function performUpkeep(bytes calldata) external override {
        require(
            block.timestamp > end_time &&
                deposited_TokenA > 0 &&
                deposited_TokenB > 0,
            "fund raising time is not over or no deposit"
        );

        uint256 lp_supply = totalSupply();
        require(lp_supply == 0, "pool has been initialized");
        reserveA = deposited_TokenA;
        reserveB = deposited_TokenB;
        lp_supply = reserveB;
        mint(tokenB_provider, lp_supply);
        console.log("mint lp supply %s to tokenB provider", lp_supply);

        // transfer LP to user who deposit tokenA
        for (uint256 i = 0; i < tokenA_deposit_address.length; i++) {
            address user_addr = tokenA_deposit_address[i];
            uint256 deposit_amount = tokenA_deposit[user_addr];
            // unchecked {
            uint256 lp_amount = (deposit_amount * lp_supply) / reserveA;
            mint(user_addr, lp_amount);
            console.log("mint lp amount %s to tokenA deposit user", lp_amount);
            // }
        }
    }
}
