
use starknet::ContractAddress;

trait ERC20InternalTrait<TContractState> {
    fn __erc20_initialize(ref self: erc20::ComponentState<TContractState>, name: felt252, symbol: felt252, decimals: u8);
    fn _transfer(ref self: erc20::ComponentState<TContractState>, sender: ContractAddress, recipient: ContractAddress, amount: u256);
    fn _approve(ref self: erc20::ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress, amount: u256);
    fn _mint(ref self: erc20::ComponentState<TContractState>, recipient: ContractAddress, amount: u256);
    fn _burn(ref self: erc20::ComponentState<TContractState>, account: ContractAddress, amount: u256);
    fn _spend_allowance(ref self: erc20::ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress, added_value: u256);
}

#[starknet::component]
mod erc20 {
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    use uniswap_v2::erc20::interface::IERC20;

    #[storage]
    struct Storage {
        _name: felt252,
        _symbol: felt252,
        _decimals: u8,
        _total_supply: u256,
        _balances: LegacyMap<ContractAddress, u256>,
        _allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        #[key]
        owner: ContractAddress,
        #[key]
        spender: ContractAddress,
        value: u256,
    }

    mod Errors {
        const APPROVE_FROM_ZERO: felt252 = 'ERC20: approve from 0';
        const APPROVE_TO_ZERO: felt252 = 'ERC20: approve to 0';
        const TRANSFER_FROM_ZERO: felt252 = 'ERC20: transfer from 0';
        const TRANSFER_TO_ZERO: felt252 = 'ERC20: transfer to 0';
        const BURN_FROM_ZERO: felt252 = 'ERC20: burn from 0';
        const MINT_TO_ZERO: felt252 = 'ERC20: mint to 0';
    }

    impl ERC20InternalImpl<TContractState, +HasComponent<TContractState>> of super::ERC20InternalTrait<TContractState> {
        fn __erc20_initialize(ref self: ComponentState<TContractState>, name: felt252, symbol: felt252, decimals: u8) {
            self._name.write(name);
            self._symbol.write(symbol);
            self._decimals.write(decimals);
        }

        fn _transfer(ref self: ComponentState<TContractState>, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
            assert(!sender.is_zero(), Errors::TRANSFER_FROM_ZERO);
            assert(!recipient.is_zero(), Errors::TRANSFER_TO_ZERO);
            
            self._balances.write(sender, self._balances.read(sender) - amount);
            self._balances.write(recipient, self._balances.read(recipient) + amount);

            self.emit(Transfer { from: sender, to: recipient, value: amount });
        }

        fn _approve(ref self: ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress, amount: u256) {
            assert(!owner.is_zero(), Errors::APPROVE_FROM_ZERO);
            assert(!spender.is_zero(), Errors::APPROVE_TO_ZERO);

            self._allowances.write((owner, spender), amount);
            self.emit(Approval { owner, spender, value: amount });
        }

        fn _mint(ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256) {
            assert(!recipient.is_zero(), Errors::MINT_TO_ZERO);

            self._total_supply.write(self._total_supply.read() + amount);
            self._balances.write(recipient, self._balances.read(recipient) + amount);

            self.emit(Transfer { from: Zeroable::zero(), to: recipient, value: amount });
        }

        fn _burn(ref self: ComponentState<TContractState>, account: ContractAddress, amount: u256) {
            assert(!account.is_zero(), Errors::BURN_FROM_ZERO);

            self._total_supply.write(self._total_supply.read() - amount);
            self._balances.write(account, self._balances.read(account) - amount);

            self.emit(Transfer { from: account, to: Zeroable::zero(), value: amount });
        }

        fn _spend_allowance(ref self: ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress, added_value: u256) {
            let caller = get_caller_address();

            self._approve(caller, spender, self._allowances.read((caller, spender)) + added_value);
        }
    }

    #[embeddable_as(ERC20Impl)]
    impl ERC20<TContractState, +HasComponent<TContractState>> of IERC20<ComponentState<TContractState>> {
        fn name(self: @ComponentState<TContractState>) -> felt252 {
            self._name.read()
        }

        fn symbol(self: @ComponentState<TContractState>) -> felt252 {
            self._symbol.read()
        }

        fn decimals(self: @ComponentState<TContractState>) -> u8 {
            self._decimals.read()
        }

        fn total_supply(self: @ComponentState<TContractState>) -> u256 {
            self._total_supply.read()
        }

        fn balance_of(self: @ComponentState<TContractState>, owner: ContractAddress) -> u256 {
            self._balances.read(owner)
        }

        fn allowance(self: @ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self._allowances.read((owner, spender))
        }

        fn transfer(ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn transfer_from(ref self: ComponentState<TContractState>, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self._spend_allowance(sender, caller, amount);
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ComponentState<TContractState>, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self._approve(caller, spender, amount);
            true
        }
    }
}
