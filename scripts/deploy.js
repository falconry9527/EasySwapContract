// scripts/deploy.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const [owner] = await ethers.getSigners()
  console.log("owner: ", owner.address)

  // 1. 部署 EasySwapVault
  esVault = await ethers.getContractFactory("EasySwapVault")
  esVault = await upgrades.deployProxy(esVault, { initializer: 'initialize' });
  const esVaultAddress = await esVault.address;
  console.log("esVault deployed to:", esVaultAddress);

  // 2. 部署 EasySwapOrderBook 
  let esDex = await ethers.getContractFactory("EasySwapOrderBook")
  newProtocolShare = 200;
  EIP712Name = "EasySwapOrderBook"
  EIP712Version = "1"
  esDex = await upgrades.deployProxy(esDex, [newProtocolShare, esVaultAddress, EIP712Name, EIP712Version],{initializer: 'initialize' });
  esDexAddress = await esDex.address;
  console.log("esDex deployed to:",esDexAddress);

  // 3. 部署 setOrderBook 
  await esVault.setOrderBook(esDexAddress)
  const tx = await esVault.setOrderBook(esDexAddress)
  console.log("esVault setOrderBook tx:", tx.hash)

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });