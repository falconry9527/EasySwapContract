// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OrderKey, Price, LibOrder} from "../libraries/LibOrder.sol";

interface IOrderStorage {
   
    function addOrder(
        LibOrder.Order memory order
    ) external  returns (OrderKey orderKey) ;


    function removeOrder(
        LibOrder.Order memory order
    ) external  returns (OrderKey orderKey) ;

    function getOrder(
       OrderKey orderKey
    ) external  view returns (LibOrder.DBOrder memory orderDb) ;
}
