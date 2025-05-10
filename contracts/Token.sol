// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * ERC20 standard interface.
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract Auth {
    address internal owner;
    mapping (address => bool) internal authorizations;

    constructor(address _owner) {
        owner = _owner;
        authorizations[_owner] = true;
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }

    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    function transferOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    event OwnershipTransferred(address owner);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract Token {
    address WETH;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    address TEAM;

    struct Addressables {
        address router;
        address team;
    }

    string _name;
    string _symbol;
    uint8 _decimals = 18;
    uint256 _totalSupply;

    uint256 public _maxTxAmount;
    uint256 public _maxWalletToken;

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    mapping (address => bool) isExcludedFromFees;
    mapping (address => bool) isExcludedFromTx;
    mapping (address => bool) isExcludedFromTimeLock;
    mapping (address => bool) isExcludedFromMaxTx;
    mapping (address => bool) isExcludedFromMaxWallet;

    uint256 public buyTax = 0;
    uint256 public sellTax = 0;
    uint256 feeDenominator = 100;
    uint256 public sellMultiplier = 737;

    struct Fees {
        uint256 buy;
        uint256 sell;
        uint256 multiplier;
    }

    address public autoLiquidityReceiver;
    uint256 public targetLiquidity = 20;
    uint256 targetLiquidityDenominator = 100;

    IDEXRouter public router;
    address public pair;

    bool public tradingOpen = false;

    bool public buyCooldownEnabled = true;
    uint8 public cooldownTimerInterval = 10;
    mapping (address => uint) private cooldownTimer;

    bool public swapEnabled = true;
    uint256 public swapThreshold = _totalSupply * 30 / 10000;

    bool inSwap;
    modifier swapping() { 
        inSwap = true; 
        _; 
        inSwap = false; 
    }

    constructor (
        string memory name_,
        string memory symbol_,
        uint256 memory _supply,
        uint256 memory maxTx,
        uint256 memory maxWallet,
        Fees memory fees,
        uint256 memory _targetLiquidity,
        uint8 memory cooldown,
        uint256 memory _swapThreshold,
        Addressables memory addressables
    ) Auth(msg.sender) {
        _name = name_;
        _symbol = symbol_;
        _totalSupply = _supply * 10**18;

        _maxTxAmount = maxTx > 0 ? maxTx * _totalSupply / 100 : _totalSupply;
        _maxWalletToken = maxWallet > 0 ? maxTx * _totalSupply / 100 : _totalSupply;

        buyTax = fees.buy > 0 ? fees.buy : 0;
        sellTax = fees.sell > 0 ? fees.sell : 0;
        sellMultiplier = fees.multiplier > 0 ? fees.multiplier : 737;

        TEAM = addressables.team;

        router = IDEXRouter(addressables.router);
        pair = IDEXFactory(router.factory()).createPair(router.WETH(), address(this));
        _allowances[address(this)][address(router)] = uint256(-1);

        isExcludedFromFees[msg.sender] = true;
        isExcludedFromFees[address(TEAM)] = true;

        isExcludedFromMaxTx[msg.sender] = true;
        isExcludedFromMaxTx[address(TEAM)] = true;

        isExcludedFromMaxWallet[msg.sender] = true;
        isExcludedFromMaxWallet[address(TEAM)] = true;

        isExcludedFromTimeLock[msg.sender] = true;
        isExcludedFromTimeLock[address(TEAM)] = true;
        isExcludedFromTimeLock[DEAD] = true;
        isExcludedFromTimeLock[address(this)] = true;

        autoLiquidityReceiver = msg.sender;

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external view override returns (uint8) { return _decimals; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function name() external view override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, uint256(-1));
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(_allowances[sender][msg.sender] >= amount, "Insufficent Amount");

        _allowances[sender][msg.sender] -= amount;

        return _transferFrom(sender, recipient, amount);
    }

    function setMaxWalletPercent_base1000(uint256 maxWallPercent_base1000) external onlyOwner() {
        _maxWalletToken = (_totalSupply * maxWallPercent_base1000 ) / 1000;
    }

    function setMaxTxPercent_base1000(uint256 maxTXPercentage_base1000) external onlyOwner() {
        _maxTxAmount = (_totalSupply * maxTXPercentage_base1000 ) / 1000;
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        if(!authorizations[sender] && !authorizations[recipient]){
            require(tradingOpen,"Trading not open yet");
        }

        if (!authorizations[sender] && recipient != address(this)  && recipient != address(DEAD) && recipient != pair && recipient != marketingTaxWallet && recipient != autoLiquidityReceiver){
            uint256 heldTokens = balanceOf(recipient);
            require((heldTokens + amount) <= _maxWalletToken,"Total Holding is currently limited, you can not buy that much.");}
        
        if (sender == pair &&
            buyCooldownEnabled &&
            !isExcludedFromTimeLock[recipient]) {
            require(cooldownTimer[recipient] < block.timestamp,"Please wait for 1min between two buys");
            cooldownTimer[recipient] = block.timestamp + cooldownTimerInterval;
        }

        // Checks max transaction limit
        checkMaxTx(sender, amount);

        if(shouldSwapBack()){ swapBack(); }

        // Exchange tokens
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");

        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(sender, amount,(recipient == pair)) : amount;
        _balances[recipient] = _balances[recipient].add(amountReceived);

        emit Transfer(sender, recipient, amountReceived);

        return true;
    }
    
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _balances[recipient] = _balances[recipient].add(amount);

        emit Transfer(sender, recipient, amount);

        return true;
    }

    function checkMaxTx(address sender, uint256 amount) internal view {
        require(amount <= _maxTxAmount || isExcludedFromMaxTx[sender], "TX Limit Exceeded");
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isExcludedFromFees[sender];
    }

    function takeFee(address sender, uint256 amount, bool isSell) internal returns (uint256) {
        uint256 multiplier = isSell ? sellMultiplier : 100;
        uint256 feeAmount = amount.mul(totalTax).mul(multiplier).div(feeDenominator * 100);

        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
    }

    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && _balances[address(this)] >= swapThreshold;
    }

    function clearStuckBalance(uint256 amountPercentage, address token) external authorized {
        uint256 amountETH = address(this).balance;
        uint256 amountToSwap = amountETH * amountPercentage / 100;

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(token);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value:amountToSwap}(
            0,
            path,
            address(TEAM),
            block.timestamp
        );
    }

    function clearStuckBalance_sender(uint256 amountPercentage) external authorized {
        uint256 amountETH = address(this).balance;
        payable(msg.sender).transfer(amountETH * amountPercentage / 100);
    }

    function set_sell_multiplier(uint256 multiplier) external onlyOwner {
        sellMultiplier = multiplier;
    }

    // Switch Trading Status
    function tradingStatus(bool _status) public onlyOwner {
        tradingOpen = _status;
    }

    // enable cooldown between trades
    function cooldownEnabled(bool _status, uint8 _interval) public onlyOwner {
        buyCooldownEnabled = _status;
        cooldownTimerInterval = _interval;
    }

    function swapBack() internal swapping {
        uint256 dynamicLiquidityFee = isOverLiquified(targetLiquidity, targetLiquidityDenominator) ? 0 : liquidityTax;
        uint256 amountToLiquify = swapThreshold.mul(dynamicLiquidityFee).div(totalTax).div(2);
        uint256 amountToSwap = swapThreshold.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        uint256 balanceBefore = address(this).balance;

        if(amountToSwap <= 0) {
            return;
        }

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountETH = address(this).balance.sub(balanceBefore);

        uint256 totalTax = buyTax + sellTax;
        uint256 totalETHFee = totalTax - (dynamicLiquidityFee / 2);
        
        uint256 amountBNBLiquidity = amountBNB * (dynamicLiquidityFee) / (totalBNBFee) / 2;

        if(amountToLiquify > 0){
            router.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );

            emit AutoLiquify(amountBNBLiquidity, amountToLiquify);
        }
    }

    function setIsExcludedFromFees(address holder, bool exempt) external authorized {
        isExcludedFromFees[holder] = exempt;
    }

    function setIsExcludedFromMaxTx(address holder, bool exempt) external authorized {
        isExcludedFromMaxTx[holder] = exempt;
    }

    function setIsExcludedFromTx(address holder, bool exempt) external authorized {
        isExcludedFromTx[holder] = exempt;
    }

    function setIsExcludedFromTimeLock(address holder, bool exempt) external authorized {
        isExcludedFromTimeLock[holder] = exempt;
    }

    function setIsExcludedFromMaxWallet(address holder, bool exempt) external authorized {
        isExcludedFromMaxWallet[holder] = exempt;
    }

    function setFees(Fees memory fees, uint256 _feeDenominator) external authorized {
        buyTax = fees.buy;
        sellTax = fees.sell;
        totalTax = fees.buy + fees.sell;
        feeDenominator = _feeDenominator;

        require(totalTax < feeDenominator / 3, "Fees cannot be more than 33%");
    }

    function setFeeReceivers(address _autoLiquidityReceiver, address _marketingFeeReceiver ) external authorized {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        marketingTaxWallet = _marketingFeeReceiver;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount) external authorized {
        swapEnabled = _enabled;
        swapThreshold = _amount;
    }

    function setTargetLiquidity(uint256 _target, uint256 _denominator) external authorized {
        targetLiquidity = _target;
        targetLiquidityDenominator = _denominator;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }

    function getLiquidityBacking(uint256 accuracy) public view returns (uint256) {
        return accuracy.mul(balanceOf(pair).mul(2)).div(getCirculatingSupply());
    }

    function isOverLiquified(uint256 target, uint256 accuracy) public view returns (bool) {
        return getLiquidityBacking(accuracy) > target;
    }
}