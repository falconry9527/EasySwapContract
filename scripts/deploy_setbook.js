const { ethers, upgrades } = require("hardhat")

async function main() {
  const [deployer] = await ethers.getSigners()
  console.log("deployer: ", deployer.address)

  esVaultAddress = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
  esDexAddress = "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9"
  const esVault = await ethers.getContractAt("EasySwapVault",esVaultAddress);
  const tx = await esVault.setOrderBook(esDexAddress, {gasLimit: 5000000,})
  console.log("esVault setOrderBook tx:", tx.hash)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
