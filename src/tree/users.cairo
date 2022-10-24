%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le

// Stores user balances.
@storage_var
func account_balances(user : felt, asset : felt) -> (amount : felt) {
}

// Stores user balances locked in open orders.
@storage_var
func order_balances(user : felt, asset : felt) -> (amount : felt) {
}

// Getter for user balances
// @param user : felt representation of user account address
// @param asset : felt representation of ERC20 token contract address
// @param in_account : 1 for account balances, 0 for order balances
// @return amount : token balance
@external
func get_balance{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (user : felt, asset : felt, in_account : felt) -> (amount : felt) {
    if (in_account == 1) {
        let (amount) = account_balances.read(user, asset);
        return (amount=amount);
    } else {
        let (amount) = order_balances.read(user, asset);
        return (amount=amount);
    }
}

// Setter for user balances
// @param user : felt representation of user account address
// @param asset : felt representation of ERC20 token contract address
// @param in_account : 1 for account balances, 0 for order balances
// @param amount : new token balance
@external
func set_balance{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (user : felt, asset : felt, in_account : felt, new_amount : felt) {
    if (in_account == 1) {
        account_balances.write(user, asset, new_amount);
        return ();
    } else {
        order_balances.write(user, asset, new_amount);
        return ();
    }
}

// Transfer balance from one user to another. 
// @param sender : felt representation of sender's account address
// @param recipient : felt representation of recipient's account address
// @param asset : felt representation of ERC20 token contract address
// @param amount : token balance
// @return success : 1 if successful, 0 otherwise
@external
func transfer_balance{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (sender : felt, recipient : felt, asset : felt, amount : felt) -> (success : felt) {
    let (sender_balance) = get_balance(sender, asset, 1);
    let is_sufficient = is_le(amount, sender_balance);
    let is_positive = is_le(1, amount);
    if (is_sufficient + is_positive == 2) {
        let (recipient_balance) = get_balance(recipient, asset, 1);
        set_balance(sender, asset, 1, sender_balance - amount);
        set_balance(recipient, asset, 1, recipient_balance + amount);
        return (success=1);
    } else {
        return (success=0);
    }    
}

// Transfer account balance to order balance.
// @param user : felt representation of user's account address
// @param asset : felt representation of ERC20 token contract address
// @param amount : balance to transfer to open order
// @return success : 1 if successful, 0 otherwise
@external
func transfer_to_order{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (user : felt, asset : felt, amount : felt) -> (success : felt) {
    let (balance) = get_balance(user, asset, 1);
    let is_sufficient = is_le(amount, balance);
    let is_positive = is_le(1, amount);
    if (is_sufficient + is_positive == 2) {
        let (locked_balance) = get_balance(user, asset, 0);
        set_balance(user, asset, 1, balance - amount);
        set_balance(user, asset, 0, locked_balance + amount);
        return (success=1);
    } else {
        return (success=0);
    }   
}

// Transfer order balance to account balance.
// @param user : felt representation of user's account address
// @param asset : felt representation of ERC20 token contract address
// @param amount : balance to transfer from open order to account balance
// @return success : 1 if successful, 0 otherwise
@external
func transfer_from_order{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (user : felt, asset : felt, amount : felt) -> (success : felt) {
    let (locked_balance) = get_balance(user, asset, 0);
    let is_sufficient = is_le(amount, locked_balance);
    let is_positive = is_le(1, amount);
    if (is_sufficient + is_positive == 2) {
        let (balance) = get_balance(user, asset, 1);
        set_balance(user, asset, 0, locked_balance - amount);
        set_balance(user, asset, 1, balance + amount);
        return (success=1);
    } else {
        return (success=0);
    }   
}