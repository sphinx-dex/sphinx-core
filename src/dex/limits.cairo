%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict import dict_write, dict_read
from src.dex.orders import Orders
from src.dex.structs import Limit
from src.utils.handle_revoked_refs import handle_revoked_refs

@contract_interface
namespace IStorageContract {
    // Get limit by limit ID
    func get_limit(limit_id : felt) -> (limit : Limit) {
    }
    // Set limit by limit ID
    func set_limit(limit_id : felt, new_limit : Limit) {
    }
    // Get root node by tree ID
    func get_root(tree_id : felt) -> (id : felt) {
    }
    // Set root node by tree ID
    func set_root(tree_id : felt, new_id : felt) {
    }
    // Get latest limit id
    func get_curr_limit_id() -> (id : felt) {
    }
    // Set latest limit id
    func set_curr_limit_id(new_id : felt) {
    }
}

namespace Limits {
    
    //
    // Functions
    //

    // Getter for limit price
    func get_limit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (limit_id : felt) -> (limit : Limit) {
        let (storage_addr) = Orders.get_storage_address();
        let (limit) = IStorageContract.get_limit(storage_addr, limit_id);
        return (limit=limit);
    }

    // Getter for lowest limit price in the tree
    // @param tree_id : ID of limit tree to be searched
    // @return min : node representation of lowest limit price in the tree
    func get_min{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (tree_id : felt) -> (min : Limit) {
        alloc_locals;
        let empty_limit : Limit* = gen_empty_limit();
        let (storage_addr) = Orders.get_storage_address();
        let (root_id) = IStorageContract.get_root(storage_addr, tree_id);
        if (root_id == 0) {
            return (min=[empty_limit]);
        }
        let (root) = IStorageContract.get_limit(storage_addr, root_id);
        let (min, _) = find_min(root, [empty_limit]);
        return (min=min);
    }

    // Getter for highest limit price in the tree
    // @param tree_id : ID of limit tree to be searched
    // @return max : node representation of highest limit price in the tree
    func get_max{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (tree_id : felt) -> (max : Limit) {
        alloc_locals;
        let (storage_addr) = Orders.get_storage_address();
        let (root_id) = IStorageContract.get_root(storage_addr, tree_id);
        let empty_limit: Limit* = gen_empty_limit();
        if (root_id == 0) {
            return (max=[empty_limit]);
        }
        let (root) = IStorageContract.get_limit(storage_addr, root_id);
        let (max) = find_max(curr=root);
        return (max=max);
    }

    // Insert new limit price into BST.
    // @param price : new limit price to be inserted
    // @param tree_id : ID of tree currently being traversed
    // @param tree_id : ID of current market
    // @return success : 1 if insertion was successful, 0 otherwise
    func insert{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        price : felt, tree_id : felt, market_id : felt
    ) -> (new_limit : Limit) {
        alloc_locals;
        
        let (storage_addr) = Orders.get_storage_address();
        let (id) = IStorageContract.get_curr_limit_id(storage_addr);
        tempvar new_limit: Limit* = new Limit(
            id=id, left_id=0, right_id=0, price=price, total_vol=0, length=0, head_id=0, tail_id=0, tree_id=tree_id, market_id=market_id
        );
        IStorageContract.set_limit(storage_addr, id, [new_limit]);
        IStorageContract.set_curr_limit_id(storage_addr, id + 1);
        
        let (root_id) = IStorageContract.get_root(storage_addr, tree_id);
        if (root_id == 0) {
            IStorageContract.set_root(storage_addr, tree_id, new_limit.id);

            // Diagnostics
            // let (new_root) = IStorageContract.get_limit(storage_addr, new_limit.id);
            // print_limit_tree(new_root, 1);

            return (new_limit=[new_limit]);
        }
        let (root) = IStorageContract.get_limit(storage_addr, root_id);
        let (inserted) = insert_helper(price, root, new_limit.id, tree_id, market_id);

        // Diagnostics
        // let (new_root) = IStorageContract.get_limit(storage_addr, root_id);
        // print_limit_tree(inserted, 1);

        return (new_limit=inserted);
    }

    // Recursively finds correct position for new limit price in BST and inserts it. 
    // @param price : new price to be inserted
    // @param curr : current node in traversal of the BST
    // @param new_limit_id : id of new node to be inserted into the BST
    // @param tree_id : ID of tree currently being traversed
    // @param market_id : ID of current market
    // @return success : 1 if insertion was successful, 0 otherwise
    func insert_helper{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        price : felt, curr : Limit, new_limit_id : felt, tree_id : felt, market_id : felt
    ) -> (new_limit : Limit) {
        alloc_locals;
        let (storage_addr) = Orders.get_storage_address();
        let (root_id) = IStorageContract.get_root(storage_addr, tree_id);
        let (root) = IStorageContract.get_limit(storage_addr, root_id);

        let greater_than = is_le(curr.price, price - 1);
        let less_than = is_le(price, curr.price - 1);

        if (greater_than == 1) {
            if (curr.right_id == 0) {
                tempvar new_curr: Limit* = new Limit(
                    id=curr.id, left_id=curr.left_id, right_id=new_limit_id, price=curr.price, total_vol=curr.total_vol, 
                    length=curr.length, head_id=curr.head_id, tail_id=curr.tail_id, tree_id=tree_id, market_id=curr.market_id
                );
                IStorageContract.set_limit(storage_addr, curr.id, [new_curr]);
                handle_revoked_refs();
                let (new_limit) = IStorageContract.get_limit(storage_addr, new_limit_id);
                return (new_limit=new_limit);
            } else {
                let (curr_right) = IStorageContract.get_limit(storage_addr, curr.right_id);
                handle_revoked_refs();
                return insert_helper(price, curr_right, new_limit_id, tree_id, market_id);
            }
        } else {
            handle_revoked_refs(); 
        }
        
        if (less_than == 1) {
            if (curr.left_id == 0) {
                tempvar new_curr: Limit* = new Limit(
                    id=curr.id, left_id=new_limit_id, right_id=curr.right_id, price=curr.price, total_vol=curr.total_vol, 
                    length=curr.length, head_id=curr.head_id, tail_id=curr.tail_id, tree_id=tree_id, market_id=curr.market_id
                );
                IStorageContract.set_limit(storage_addr, curr.id, [new_curr]);
                handle_revoked_refs();
                let (new_limit) = IStorageContract.get_limit(storage_addr, new_limit_id);
                return (new_limit=new_limit);
            } else {
                let (curr_left) = IStorageContract.get_limit(storage_addr, curr.left_id);
                handle_revoked_refs();
                return insert_helper(price, curr_left, new_limit_id, tree_id, market_id);
            }
        } else {
            handle_revoked_refs(); 
        }

        let empty_limit: Limit* = gen_empty_limit();
        return (new_limit=[empty_limit]);
    }

    // Find a limit price in binary search tree.
    // @param price : limit price to be found
    // @param tree_id : ID of tree currently being traversed
    // @return limit : retrieved limit price (or empty limit if not found)
    // @return parent : parent of retrieved limit price (or empty limit if not found)
    func find{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        price : felt, tree_id : felt
    ) -> (limit : Limit, parent : Limit) {
        alloc_locals;
        let (storage_addr) = Orders.get_storage_address();
        let (root_id) = IStorageContract.get_root(storage_addr, tree_id);
        let empty_limit: Limit* = gen_empty_limit();
        if (root_id == 0) {
            return (limit=[empty_limit], parent=[empty_limit]);
        }
        let (root) = IStorageContract.get_limit(storage_addr, root_id);
        return find_helper(tree_id=tree_id, price=price, curr=root, parent=[empty_limit]);
    }

    // Recursively traverses BST to find limit price.
    // @param tree_id : ID of tree currently being traversed
    // @param price : limit price to be found
    // @param curr : current node in traversal of the BST
    // @param parent : parent of current node in traversal of the BST
    // @return limit : retrieved limit price (or empty limit if not found)
    // @return parent : parent of retrieved limit price (or empty limit if not found)
    func find_helper{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        tree_id : felt, price : felt, curr : Limit, parent : Limit
    ) -> (limit : Limit, parent : Limit) {
        alloc_locals;

        let (storage_addr) = Orders.get_storage_address();
        if (curr.id == 0) {
            let empty_limit: Limit* = gen_empty_limit();
            handle_revoked_refs();
            return (limit=[empty_limit], parent=[empty_limit]);
        } else {
            handle_revoked_refs();
        }    

        let greater_than = is_le(curr.price, price - 1);
        if (greater_than == 1) {
            let (curr_right) = IStorageContract.get_limit(storage_addr, curr.right_id);
            handle_revoked_refs();
            return find_helper(tree_id, price, curr_right, curr);
        } else {
            handle_revoked_refs();
        }

        let less_than = is_le(price, curr.price - 1);
        if (less_than == 1) {
            let (curr_left) = IStorageContract.get_limit(storage_addr, curr.left_id);
            handle_revoked_refs();
            return find_helper(tree_id, price, curr_left, curr);
        } else {
            handle_revoked_refs();
        }

        return (limit=curr, parent=parent);
    }

    // Deletes limit price from BST
    // @param price : limit price to be deleted
    // @param tree_id : ID of tree currently being traversed
    // @param market_id : ID of current market
    // @return del : node representation of deleted limit price
    func delete{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        price : felt, tree_id : felt, market_id : felt
    ) -> (del : Limit) {
        alloc_locals;

        let empty_limit: Limit* = gen_empty_limit();
        let (storage_addr) = Orders.get_storage_address();
        let (root_id) = IStorageContract.get_root(storage_addr, tree_id);
        if (root_id == 0) {
            handle_revoked_refs();
            return (del=[empty_limit]);
        } else {
            handle_revoked_refs();
        }

        let (limit, parent) = find(price, tree_id);
        if (limit.id == 0) {
            return (del=[empty_limit]);
        }

        if (limit.left_id == 0) {
            if (limit.right_id == 0) {
                update_parent(tree_id=tree_id, parent=parent, limit=limit, new_id=0);
                handle_revoked_refs();
            } else {
                update_parent(tree_id=tree_id, parent=parent, limit=limit, new_id=limit.right_id);
                handle_revoked_refs();
            }
        } else {
            if (limit.right_id == 0) {
                update_parent(tree_id=tree_id, parent=parent, limit=limit, new_id=limit.left_id);
                handle_revoked_refs();
            } else {
                let (right) = IStorageContract.get_limit(storage_addr, limit.right_id);
                let (successor, successor_parent) = find_min(right, limit);

                update_parent(tree_id=tree_id, parent=parent, limit=limit, new_id=successor.id);
                if (limit.left_id == successor.id) {                
                    update_pointers(successor, 0, limit.right_id);
                } else {
                    if (limit.right_id == successor.id) {
                        update_pointers(successor, limit.left_id, 0);                    
                    } else {
                        update_pointers(successor, limit.left_id, limit.right_id);
                    }   
                }
                update_parent(tree_id=tree_id, parent=successor_parent, limit=successor, new_id=0);
            }
        }

        // Diagnostics
        // let (root_id) = IStorageContract.get_root(storage_addr, tree_id);
        // let (new_root) = IStorageContract.get_limit(storage_addr, root_id);
        // print_limit_tree(new_root, 1);

        return (del=limit);
    }

    // Helper function to update left or right child of parent.
    // @param tree_id : ID of tree currently being traversed
    // @param parent : parent node to update
    // @param limit : current node to be replaced
    // @param new_id : id of the new node that parent should point to
    func update_parent{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        tree_id : felt, parent : Limit, limit : Limit, new_id : felt
    ) {
        alloc_locals;

        let (storage_addr) = Orders.get_storage_address();
        if (parent.id == 0) {
            IStorageContract.set_root(storage_addr, tree_id, new_id);
            handle_revoked_refs();
        } else {
            handle_revoked_refs();
        }

        if (parent.left_id == limit.id) {
            update_pointers(parent, new_id, parent.right_id);
        } else {
            update_pointers(parent, parent.left_id, new_id);
        }

        return ();
    }

    // Helper function to update left and right pointer of a node.
    // @param node : current node to update
    // @param left_id : id of new left child
    // @param right_id : id of new right child
    func update_pointers{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        node : Limit, left_id : felt, right_id : felt
    ) {
        tempvar new_node: Limit* = new Limit(
            id=node.id, left_id=left_id, right_id=right_id, price=node.price, total_vol=node.total_vol, 
            length=node.length, head_id=node.head_id, tail_id=node.tail_id, tree_id=node.tree_id, market_id=node.market_id
        );
        let (storage_addr) = Orders.get_storage_address();
        IStorageContract.set_limit(storage_addr, node.id, [new_node]);
        handle_revoked_refs();
        return ();
    }

    // Helper function to find the lowest limit price within a tree
    // @param root : root of tree to be searched
    // @param parent : parent node of root
    // @return min : node representation of lowest limit price
    // @return parent : parent node of lowest limit price
    func find_min{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        curr : Limit, parent : Limit
    ) -> (min : Limit, parent : Limit) {
        if (curr.left_id == 0) {
            return (min=curr, parent=parent);
        }
        let (storage_addr) = Orders.get_storage_address();
        let (left) = IStorageContract.get_limit(storage_addr, curr.left_id);
        return find_min(curr=left, parent=curr);
    }

    // Helper function to find the highest limit price within a tree
    // @param root : root of tree to be searched
    // @return min : node representation of highest limit price
    func find_max{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (curr : Limit) -> (max : Limit) {
        if (curr.right_id == 0) {
            return (max=curr);
        }
        let (storage_addr) = Orders.get_storage_address();
        let (right) = IStorageContract.get_limit(storage_addr, curr.right_id);
        return find_max(curr=right);
    }

    // Setter function to update details of limit price
    // @param limit : ID of limit price to update
    // @param new_vol : new volume
    // @return success : 1 if successfully inserted, 0 otherwise
    func update{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        limit_id : felt, total_vol : felt, length : felt, head_id : felt, tail_id : felt) -> (success : felt
    ) {
        if (limit_id == 0) {
            return (success=0);
        }
        let (storage_addr) = Orders.get_storage_address();
        let (limit) = IStorageContract.get_limit(storage_addr, limit_id);
        tempvar new_limit: Limit* = new Limit(
            id=limit.id, left_id=limit.left_id, right_id=limit.right_id, price=limit.price, total_vol=total_vol, 
            length=length, head_id=head_id, tail_id=tail_id, tree_id=limit.tree_id, market_id=limit.market_id
        );
        IStorageContract.set_limit(storage_addr, limit_id, [new_limit]);
        return (success=1);
    }

    // Helper function to generate an empty limit struct.
    func gen_empty_limit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} () -> (empty_limit : Limit*) {
        tempvar empty_limit: Limit* = new Limit(
            id=0, left_id=0, right_id=0, price=0, total_vol=0, length=0, head_id=0, tail_id=0, tree_id=0, market_id=0
        );
        return (empty_limit=empty_limit);
    }

    // Utility function to return all limit prices and volumes in a limit tree, from left to right order.
    // @param tree_id : ID of tree to be viewed
    // @return prices : array of limit prices
    // @return amounts : array of order volumes at each limit price
    // @return length : length of limit tree in number of nodes
    func view_limit_tree{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        tree_id : felt
    ) -> (prices : felt*, amounts : felt*, length : felt) {
        alloc_locals;

        let (storage_addr) = Orders.get_storage_address();
        let (root_id) = IStorageContract.get_root(storage_addr, tree_id);
        let (root) = IStorageContract.get_limit(storage_addr, root_id);

        let (prices : felt*) = alloc();
        let (amounts : felt*) = alloc();

        let (left) = IStorageContract.get_limit(storage_addr, root.left_id);
        let (left_length) = get_limit_tree_length(left);
        view_limit_tree_helper{prices=prices, amounts=amounts}(node=root, idx=left_length);

        let (length) = get_limit_tree_length(root);
        return (prices=prices, amounts=amounts, length=length);
    }

    // Helper function to retrieve limit tree
    // @param node : node in current iteration of function (starts from root)
    // @param idx : node index for matching prices with amounts (unsorted)
    func view_limit_tree_helper{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*, 
        range_check_ptr, 
        prices : felt*,
        amounts : felt*,
    } (node : Limit, idx : felt) {
        alloc_locals;

        let (storage_addr) = Orders.get_storage_address();
        if (node.left_id == 0) {
            handle_revoked_refs_alt();
        } else {
            let (left) = IStorageContract.get_limit(storage_addr, node.left_id);
            let (left_right_child) = IStorageContract.get_limit(storage_addr, left.right_id);
            let (left_right_child_length) = get_limit_tree_length(left_right_child);
            view_limit_tree_helper(left, idx - left_right_child_length - 1);
            handle_revoked_refs_alt();
        }

        if (node.right_id == 0) {
            handle_revoked_refs_alt();
        } else {
            handle_revoked_refs_alt();
            let (right) = IStorageContract.get_limit(storage_addr, node.right_id);
            let (right_left_child) = IStorageContract.get_limit(storage_addr, right.left_id);
            let (right_left_child_length) = get_limit_tree_length(right_left_child);
            view_limit_tree_helper(right, idx + right_left_child_length + 1);
        }

        assert prices[idx] = node.price;
        assert amounts[idx] = node.total_vol;

        return ();
    }

    // Helper function to get length of limit tree
    // @param node : node in current iteration of function (starts from root)
    // @return length : length of limit tree
    func get_limit_tree_length{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        node : Limit
    ) -> (length : felt) {
        alloc_locals;
        let (storage_addr) = Orders.get_storage_address();
        if (node.id == 0) {
            return (length=0);
        } else {
            let (left) = IStorageContract.get_limit(storage_addr, node.left_id);
            let (right) = IStorageContract.get_limit(storage_addr, node.right_id);
            let (left_length) = get_limit_tree_length(left);
            let (right_length) = get_limit_tree_length(right);
            return (length=1+left_length+right_length);
        }
    }

    // Utility function to return all orders in a limit tree, from left to right.
    // @param tree_id : ID of tree to be viewed
    // @return prices : array of limit prices
    // @return amounts : array of order volumes 
    // @return owners : array of order owners
    // @return ids : array of order ids
    // @return length : length of limit tree in number of orders
    func view_limit_tree_orders{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        tree_id : felt
    ) -> (prices : felt*, amounts : felt*, owners: felt*, ids: felt*, length : felt) {
        alloc_locals;

        let (storage_addr) = Orders.get_storage_address();
        let (root_id) = IStorageContract.get_root(storage_addr, tree_id);
        let (root) = IStorageContract.get_limit(storage_addr, root_id);

        let (prices : felt*) = alloc();
        let (amounts : felt*) = alloc();
        let (owners : felt*) = alloc();
        let (ids : felt*) = alloc();

        let (left) = IStorageContract.get_limit(storage_addr, root.left_id);
        let (left_length) = get_limit_tree_order_length(left);

        view_limit_tree_orders_helper{prices=prices, amounts=amounts, owners=owners, ids=ids}(node=root, idx=left_length);

        let (length) = get_limit_tree_order_length(root);
        return (prices=prices, amounts=amounts, owners=owners, ids=ids, length=length);
    }

    // Helper function to retrieve limit tree orders
    // @param node : node in current iteration of function (starts from root)
    // @param idx : node index for matching prices with amounts (unsorted)
    func view_limit_tree_orders_helper{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*, 
        range_check_ptr, 
        prices : felt*,
        amounts : felt*,
        owners : felt*,
        ids : felt*,
    } (node : Limit, idx : felt) {
        alloc_locals;

        let (storage_addr) = Orders.get_storage_address();
        if (node.left_id == 0) {
            handle_revoked_refs_alt_2();
        } else {
            let (left) = IStorageContract.get_limit(storage_addr, node.left_id);
            let (left_right_child) = IStorageContract.get_limit(storage_addr, left.right_id);
            let (left_right_child_length) = get_limit_tree_order_length(left_right_child);
            view_limit_tree_orders_helper(left, idx - left_right_child_length - left.length);
            handle_revoked_refs_alt_2();
        }

        if (node.right_id == 0) {
            handle_revoked_refs_alt_2();
        } else {
            handle_revoked_refs_alt_2();
            let (right) = IStorageContract.get_limit(storage_addr, node.right_id);
            let (right_left_child) = IStorageContract.get_limit(storage_addr, right.left_id);
            let (right_left_child_length) = get_limit_tree_order_length(right_left_child);
            view_limit_tree_orders_helper(right, idx + right_left_child_length + node.length);
        }
        
        fill_orders_helper(node.head_id, idx);
        
        return ();
    }

    func fill_orders_helper{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*, 
        range_check_ptr, 
        prices : felt*,
        amounts : felt*,
        owners : felt*,
        ids : felt*,
    } (curr_order_id : felt, idx : felt) {
        alloc_locals;
        
        let (storage_addr) = Orders.get_storage_address();
        let (curr) = Orders.get_order(curr_order_id);

        assert prices[idx] = curr.price;
        assert amounts[idx] = curr.amount;
        assert owners[idx] = curr.owner;
        assert ids[idx] = curr.id;

        if (curr.next_id == 0) {
            handle_revoked_refs_alt_2();
        } else {
            handle_revoked_refs_alt_2();
            fill_orders_helper(curr.next_id, idx + 1);
        }
        return ();
    }

    // Helper function to get length of limit tree in number of orders
    // @param node : node in current iteration of function (starts from root)
    // @return length : length of limit tree in number of orders
    func get_limit_tree_order_length{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        node : Limit
    ) -> (length : felt) {
        alloc_locals;
        let (storage_addr) = Orders.get_storage_address();
        if (node.id == 0) {
            return (length=0);
        } else {
            let (left) = IStorageContract.get_limit(storage_addr, node.left_id);
            let (right) = IStorageContract.get_limit(storage_addr, node.right_id);
            let (left_length) = get_limit_tree_order_length(left);
            let (right_length) = get_limit_tree_order_length(right);
            return (length=node.length+left_length+right_length);
        }
    }

    // Utility function to handle revoked implicit references.
    // @dev Amended from regular version to include prices and amounts
    func handle_revoked_refs_alt{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*, 
        range_check_ptr,
        prices : felt*,
        amounts : felt*,
    } () {
        tempvar syscall_ptr=syscall_ptr;
        tempvar pedersen_ptr=pedersen_ptr;
        tempvar range_check_ptr=range_check_ptr;
        tempvar prices=prices;
        tempvar amounts=amounts;
        return ();
    }

    // Utility function to handle revoked implicit references.
    // @dev Amended from regular version to include prices, amounts, orders and ids
    func handle_revoked_refs_alt_2{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*, 
        range_check_ptr,
        prices : felt*,
        amounts : felt*,
        owners : felt*,
        ids : felt*,
    } () {
        tempvar syscall_ptr=syscall_ptr;
        tempvar pedersen_ptr=pedersen_ptr;
        tempvar range_check_ptr=range_check_ptr;
        tempvar prices=prices;
        tempvar amounts=amounts;
        tempvar owners=owners;
        tempvar ids=ids;
        return ();
    }

}