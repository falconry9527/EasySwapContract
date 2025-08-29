#  脚本

### 常规脚本
```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.js
```

### 链上部署脚本
```shell
1. 部署 EasySwapVault 和 EasySwapOrderBook
npx hardhat run scripts/deploy.js  --network sepolia

1. 关联两个合约
npx hardhat run scripts/deploy_setbook.js  --network sepolia

```

### 测试脚本
```shell
npm cache clean --force
npx hardhat clean && npx hardhat compile
npx hardhat test test/testEasySwap_make.js   --network sepolia
npx hardhat test test/testEasySwap_match.js 
```

# 合约架构整理
```
--- EasySwapOrderBook: 业务逻辑层
1.makeOrders : 下单
2.matchOrders : 匹配订单
3.editOrders : 编辑订单
4.cancelOrders : 取消订单

--- OrderStorage : 数据存储层
// (订单key-> 订单的详细信息)
mapping(OrderKey => LibOrder.DBOrder) public orders;

// 买入和卖出的价格排序
// 买入/卖出 -> 价格树
mapping(address => mapping(LibOrder.Side => RedBlackTreeLibrary.Tree)) public priceTrees;

// 订单队列： 买入/卖出 -> （价格-> 价格队列）
mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue))) public orderQueues;

--- EasySwapVault : 钱包和转账层
ETHBalance：用户eth余额
NFTBalance：用户nft余额
depositETH : 存入NFT
withdrawNFT :  取出NFT

---OrderValidator: 订单验证器
// 订单号 -> 订单金额 ：CANCELLED 为 已经取消
mapping(OrderKey => uint256) public filledAmount;

---ProtocolManager: 管理协议费
protocolShare : 手续费

```

# 数据结构
### 二叉搜索树 (BST) 
```
每个节点最多有两个子节点，且满足：左子节点 < 父节点 < 右子节点。
缺点： 当连续插入一段数据后，会退化成链表

```
### 红黑树 (RBT)
```
是一种自平衡的BST，额外增加了颜色属性（红/黑）和一系列平衡规则。
设定规则：用“黑色高度相同”和“红色不相邻”两条核心规则作为平衡的衡量标准。
违规触发：一旦插入或删除操作导致树的结构可能趋向不平衡（表现为违反了规则），修复机制立刻被触发。
旋转调整：通过旋转操作来改变树的结构，物理上降低树的高度，消除长链。
变色维持：通过变色操作来满足颜色规则，同时保证旋转后黑色高度不变。
```
### B+Tree
```
B+Tree是多路搜索树，一个节点可以有M个分支（M可能为100甚至更大）
```

# EVM 数据存储
```
Calldata
这是一个特殊的、只读的区域，用于存储触发合约执行的原始交易数据。

memory : EVM自身的内存,临时存储，函数执行期间有效
主要存储 : 存储函数的参数和返回值。

Stack : 栈是 EVM 执行计算的核心区域,有1024个slot
存储局部变量(如果是值类型，如 uint, bool)；存储计算过程中的中间结果。

Storage : 持久化存储在区块链上，因此操作它需要消耗 Gas，且非常昂贵。
主要存储：映射 (Mapping)，动态数组 等全局变量

Stack 特例 ：
可知长度的数组 ：直接存储值（int a=3）
未知长度的数组 ：存储一个keccack256的 hash值
,指向memory或storage（int [] arr ）
```

# gas 优化
```
1. 使用事件（Event）来记录不需要链上访问的历史数据。
2. 尽可能使用 memory 和 calldata 。
3. 利用存储打包，将多个小尺寸变量声明在一起,放在一个槽中。
一个存储槽 = 32 字节（256 位）
存储打包：如果多个连续声明的状态变量的大小总和小于或等于 32 字节，EVM 会尝试将它们“打包”到同一个存储槽中，而不是每个变量独占一个槽。


```




