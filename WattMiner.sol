// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./TransferHelper.sol";
import "./ITRC20.sol";
import "./LpWallet.sol";
import "./LizMinePool.sol";

contract WattMiner is ReentrancyGuard {
    using TransferHelper for address;
    using SafeMath for uint256;

    address private _Wattaddr;
    address payable private _owner;
    address private _feeowner;
    LizMinePool private _minepool;

    mapping(uint256 => uint256[20]) internal _levelconfig; //credit level config

    uint256 _nowtotalhash;

    mapping(uint256 => uint256[3]) _checkpoints;

    uint256 _currentMulitiper;
    uint256 _maxcheckpoint;
    uint256 _minNum;
    uint256 _lpPeople;
    

    uint private closeBlock = 0; //项目方设置可提时间

    mapping(address => mapping(address => uint256)) _userLphash;
    mapping(address => mapping(address => uint256)) _userLpBlock;
    mapping(address => mapping(address => uint256)) _userLpPending;
    mapping(address => mapping(address => uint256)) _useralreadyget;//用户矿池已经领取token

    mapping(address => mapping(uint256 => uint256)) _userlevelhashtotal; // level hash in my team
    mapping(address => address) internal _parents; //Inviter
    mapping(address => UserInfo) _userInfos;
    mapping(address => PoolInfo) _lpPools;
    mapping(address => address[]) _mychilders;
    mapping(address => uint256) _tokennowtotalhash;//当前矿池总算力
    mapping(address => uint256) _tokennowtotalwidth;//当前矿池wachu
    address[] _lpaddresses;

    struct PoolInfo {
        LpWallet poolwallet;
        uint256 hashrate; //  The LP hashrate
    }

    uint256[2] _vipbuyprice = [0, 50];


     struct UserInfo {
        uint256 selfhash; //user hash total count
        uint256 teamhash;
        uint256 userlevel; // my userlevel
        uint256 pendingreward;
        uint256 lastblock;
        uint256 lastcheckpoint;
    }

    event BindingParents(address indexed user, address inviter);
    event VipChanged(address indexed user, uint256 userlevel);
    event TradingPooladded(address indexed tradetoken);
    event UserBuied(
        address indexed tokenaddress,
        uint256 amount
    );
    event TakedBack(address indexed tokenaddress, uint256 pct);

    //项目方规定时间之后可操作
    modifier afterCloseBlock(){
        require(block.number > closeBlock);
        _;
    }


    constructor() public {
        closeBlock = block.number + 980000;  //合约部署多少块之后可操作提现
        // closeBlock = block.number;  //合约部署多少块之后可操作提现
        _owner = msg.sender;
        _lpPeople = 1;
    }

    
    function getMinerPoolAddress() public view returns (address) {
        return address(_minepool);
    }

     function getMyChilders(address user)
        public
        view
        returns (address[] memory)
    {
        return _mychilders[user];
    }

     function into(uint256 amount) public payable {
        _Wattaddr.safeTransferFrom(msg.sender, address(this), amount);
    }

    function InitalContract(
        address WattToken,
        address feeowner
    ) public {
        require(msg.sender == _owner);
        require(_feeowner == address(0));
        _Wattaddr = WattToken;
        _feeowner = feeowner;
        _minepool = new LizMinePool(WattToken, _owner);
        _parents[msg.sender] = address(_minepool);

        _levelconfig[0] = [
            50,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ];
        _levelconfig[1] = [
            50,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ];
    }

    //修正矿池
    function fixTradingPool(
        address tokenAddress,
        uint256 rate
    ) public returns (bool) {
        require(msg.sender == _owner);
        _lpPools[tokenAddress].hashrate = rate;
        return true;
    }
    //添加矿池
     function addTradingPool(
        address tokenAddress,
        uint256 rate
    ) public returns (bool) {
        require(msg.sender == _owner);
        require(rate > 0, "ERROR RATE");
        require(_lpPools[tokenAddress].hashrate == 0, "LP EXISTS");

        LpWallet wallet =
            new LpWallet(tokenAddress, _Wattaddr, _feeowner, _owner);
        _lpPools[tokenAddress] = PoolInfo({
            poolwallet: wallet,
            hashrate: rate
        });
        _lpaddresses.push(tokenAddress);
        _tokennowtotalhash[tokenAddress] = 0;//初始化当前矿池总量
        emit TradingPooladded(tokenAddress);
        return true;
    }

     //******************Getters ******************/
    function getParent(address user) public view returns (address) {
        return _parents[user];
    }
    //获取代币token总质押算力
    function getTotalHash(address tokenAddress) public view returns (uint256) {
        return _tokennowtotalhash[tokenAddress];
    }

    function getMyLpInfo(address user, address tokenaddress)
        public
        view
        returns (uint256[4] memory)
    {
        uint256[4] memory bb;
        bb[0] = _lpPools[tokenaddress].poolwallet.getBalance(user, true);
        bb[1] = _lpPools[tokenaddress].poolwallet.getBalance(user, false);
        bb[2] = _userLphash[user][tokenaddress];
        bb[3] =  _userLpBlock[user][tokenaddress];
        return bb;
    }
    //获取用户个人算力
    function getUserSelfHash(address user, address tokenaddress) public view returns (uint256) {
        return _userLphash[user][tokenaddress];
    }
    //获取个人已赚取
    function getMyalready(address user,address tokenAddress) public view returns(uint256){
        return _useralreadyget[user][tokenAddress];
    }
    //获取手续费地址
    function getFeeOnwer() public view returns (address) {
        return _feeowner;
    }
    //获取质押矿池地址
    function getWalletAddress(address lptoken) public view returns (address) {
        return address(_lpPools[lptoken].poolwallet);
    }

    //设置释放数量
    function setMinNum(uint256 minNum) public returns(bool){
        require(minNum >= 10000000000, "too less");
        _minNum = minNum;
        return true;
    }
    //获取释放数量
    function getMinNum() public view returns(uint256){
        return _minNum;
    }
    function getlpPeople() public view returns(uint256){
        return _lpPeople;
    }

    function getTotalwidth(address tokenAddress) public view returns(uint256){
        return _tokennowtotalwidth[tokenAddress];
    }

    //建立关系
    function bindParent(address parent) public {
        require(_parents[msg.sender] == address(0), "Already bind");
        require(parent != address(0), "ERROR parent");
        require(parent != msg.sender, "error parent");
        require(_parents[parent] != address(0));
        _parents[msg.sender] = parent;
        _mychilders[parent].push(msg.sender);
        _lpPeople = _lpPeople.add(1);
        emit BindingParents(msg.sender, parent);
    }

    function SetParentByAdmin(address user, address parent) public {
        require(_parents[user] == address(0), "Already bind");
        require(msg.sender == _owner);
        _parents[user] = parent;
        _mychilders[parent].push(user);
    }
    
    //修改个人算力
    function setMemberHash(address user , address tokenaddress , uint256 hashnum) public returns(bool){
        require(msg.sender == _owner , "no rule");
        _userLphash[user][tokenaddress] = hashnum;
        return true;
    }



    //质押
    function deposit(
        address tokenAddress,
        uint256 amount
    ) public payable nonReentrant returns (bool) {
        require(amount > 10000);
        uint256 abcbalance = ITRC20(tokenAddress).balanceOf(msg.sender);
        require(abcbalance >= amount, "balance too less");
        tokenAddress.safeTransferFrom(
            msg.sender,
            address(_lpPools[tokenAddress].poolwallet),
            amount
        );
        _lpPools[tokenAddress].poolwallet.addBalance(
            msg.sender,
            amount,
            0
        );
        //个人修改算力值
        UserHashChanged(msg.sender, tokenAddress,amount,true, block.number);        
        address parent = _parents[msg.sender];
        if(parent != address(0)){
            //给上级用户添加数量
            uint256 amountUp = amount.div(100).mul(5);
            //上级修改算力值
            UserHashChanged(parent, tokenAddress,amountUp,true, block.number);  
        }
        emit UserBuied(tokenAddress, amount);
        return true;
    }

    function UserHashChanged(
        address user,
        address tokenAddress,
        uint256 selfhash,
        bool add,
        uint256 blocknum
    ) private {
       //用户待领取代币
        uint256 dash = getPendingCoin(user,tokenAddress);
        _userLpPending[user][tokenAddress] = dash;
        //用户当前操作区块
        _userLpBlock[user][tokenAddress] = blocknum;
        if (selfhash > 0) {
            if (add) {
                //个人算力添加数量
                _userLphash[user][tokenAddress] = _userLphash[user][
                tokenAddress].add(selfhash);
                //token矿池添加总数
                _tokennowtotalhash[tokenAddress] = 
                _tokennowtotalhash[tokenAddress].add(selfhash);
            } else{
                //个人算力减少数量
                _userLphash[user][tokenAddress] = _userLphash[user][
                tokenAddress].sub(selfhash);
                //token矿池减少总数
                _tokennowtotalhash[tokenAddress] = 
                _tokennowtotalhash[tokenAddress].sub(selfhash);
            } 
        }
    }

    function getPendingCoin(address user, address tokenAddress) public view returns (uint256) {
        if (_userLpBlock[user][tokenAddress] == 0) {
            return 0;
        }
        
        uint256 total = _userLpPending[user][tokenAddress];
        //个人算力
        if ( _userLphash[user][tokenAddress] == 0) return total;
        //最后操作区块
        uint256 lastblock = _userLpBlock[user][tokenAddress];
        
        if (block.number > lastblock) {
            //统计区块数量
            uint256 blockcount = block.number.sub(lastblock);
            //计算待领取代币数量  个人质押算力/全网质押算力 * 单块(3800 / 28000)*块数
            uint256 OneBlockReward = _minNum.div(28000).mul(blockcount);
            uint256 getk =  _userLphash[user][tokenAddress].mul(1e8)
                        .div(_tokennowtotalhash[tokenAddress]).mul(OneBlockReward);
            uint256 getkNew = getk.div(1e8);
            if(getkNew>0){
                total = total.add(getkNew);
            }
        }
        return total;
    }
    //提现
    function WithDrawCredit(address tokenAddress) public nonReentrant returns (bool) {
        require(block.number > closeBlock ,"too early");
        uint256 amount = getPendingCoin(msg.sender,tokenAddress);
        if (amount < 100) return true;
        //将用户数量清零 区块更新 已领取数量更新
        _userLpPending[msg.sender][tokenAddress] = 0;
        _userLpBlock[msg.sender][tokenAddress] = block.number;
        _useralreadyget[msg.sender][tokenAddress] = 
            _useralreadyget[msg.sender][tokenAddress].add(amount);
        //将上级区块更新
        
        _tokennowtotalwidth[tokenAddress] = _tokennowtotalwidth[tokenAddress].add(amount);
        _minepool.MineOut(msg.sender, amount);
        return true;
    }

    //赎回代币
    function TakeBack(address tokenAddress, uint256 pct)
        public
        nonReentrant
        returns (bool)
    {
        require(pct >= 10000 && pct <= 1000000);
        require(
            _lpPools[tokenAddress].poolwallet.getBalance(msg.sender, true) >=
                10000,
            "ERROR AMOUNT"
        );
        //获取质押代币余额
        uint256 balancea =
            _lpPools[tokenAddress].poolwallet.getBalance(msg.sender, true);
        uint256 balanceb =
            _lpPools[tokenAddress].poolwallet.getBalance(msg.sender, false);

        uint256 amounta = balancea.mul(pct).div(1000000);
        uint256 decreasehash = amounta.mul(pct).div(1000000);
        //减去个人和上级算力
        UserHashChanged(msg.sender, tokenAddress,decreasehash,false, block.number);  
        address parent = _parents[msg.sender];
        if(parent != address(0)){
            //给上级用户减少算力
            uint256 updecreasehash = decreasehash.div(100).mul(5);
            //上级修改算力值
            UserHashChanged(parent, tokenAddress,updecreasehash,false, block.number);  
        }

        
        _lpPools[tokenAddress].poolwallet.TakeBack(
            msg.sender,
            amounta,
            balanceb
        );
        emit TakedBack(tokenAddress, pct);
        return true;
    }
}