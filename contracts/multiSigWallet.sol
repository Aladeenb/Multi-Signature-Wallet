// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
contract MultiSigWallet{
    event Deposit(address indexed sender, uint amount);
    event Submit(uint indexed txId);
    event Approve(address indexed owner, uint indexed txId);
    event Execute(uint indexed txId);
    event Revoke(address indexed owner, uint indexed txId);

    struct Transaction {
        address to;
        uint value;
        bytes data;
        bool executed;
    }
     
    address[] public owners;
    mapping(address => bool) public isOwner;    // Quick way to check that msg.sender is owner
    uint public requiredApprovals; // Number of approvals required to execute a tx

    Transaction[] public transactions;
    mapping(uint => mapping(address => bool)) public approved; // To check whether a tx is approved by owner

    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint _txId){  // Transaction exsits if index is less than the array 
        require(_txId < transactions.length, "transaction does not exist");
        _;
    }

    modifier notApproved(uint _txId){
        require(!approved[_txId][msg.sender], "transaction approved already");
        _;
    }

    modifier notExecuted(uint _txId){
        require(transactions[_txId].executed, "transaction executed already");
        _;
    }

    constructor(address[] memory _owners, uint _requiredApprovals){
        require(owners.length > 0, "owners required");
        require(_requiredApprovals > 0 && _requiredApprovals <= _owners.length, "invalid approval number");

        for(uint i; i < _owners.length; i++) {  // Save owners to owners[]
            address owner = _owners[i];
            require(owner != address(0), "invalid owner");  
            require(!isOwner[owner], "owner already exists / not unique");   // Owner must be distinct

            isOwner[owner] = true;
            owners.push(owner);
        }

        requiredApprovals = _requiredApprovals;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    function submit(address _to, uint _value, bytes calldata _data)
        external
        onlyOwner
        {
            transactions.push(Transaction({
                to: _to,
                value: _value,
                data: _data,
                executed: false
            }));
            emit Submit(transactions.length - 1);   // Indexing transactions: tx(n) -> index (n-1)
        }

        // Once the transaction is submitted, other owners can approve the transactions.
        function approve(uint _txId)
            external
            onlyOwner
            txExists(_txId)
            notApproved(_txId)  // Transaction is not yet approved
            notExecuted(_txId)  // Transaction is not yet executed
            {
                approved[_txId][msg.sender] = true;
                emit Approve(msg.sender, _txId);
            }

            // In order to execute a transcation, the number of approved must be greater than requiredApprovals (or maybe equal)
            function _getApprovalCount(uint _txId) private view returns (uint count) {
                for (uint i; i < owners.length; ++i) {
                    if (approved[_txId][owners[i]]) {
                        ++count;
                    }
                }
            }

            function execute(uint _txId) external txExists(_txId) notExecuted(_txId) {
                require(_getApprovalCount(_txId) >= requiredApprovals);
                
                // Store data in transaction struct and then update it
                Transaction storage transaction = transactions[_txId];

                transaction.executed = true;

                (bool success, ) = transaction.to.call{value: transaction.value}(
                    transaction.data
                );
                require(success, "transaction failed");

                emit Execute(_txId);
            }

            // Allow owner to undo approval
            function revoke(uint _txId) 
                external 
                onlyOwner 
                txExists(_txId) 
                notExecuted(_txId){
                    require(approved[_txId][msg.sender], "tx not approved");
                    approved[_txId][msg.sender] = false;
                    emit Revoke(msg.sender, _txId);
            }
}