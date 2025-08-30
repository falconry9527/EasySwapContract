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

2. 关联两个合约
npx hardhat run scripts/deploy_setbook.js  --network sepolia

```

### 测试脚本
```shell
npm cache clean --force
npx hardhat clean && npx hardhat compile
npx hardhat test test/testEasySwap_make.js   --network sepolia
npx hardhat test test/testEasySwap_match.js 
```
