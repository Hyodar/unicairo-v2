trait PairInternalTrait<TContractState> {
    fn _update(ref self: TContractState, balance0: u128, balance1: u128, reserve0: u128, reserve1: u128);
    fn _mint_fee(ref self: TContractState, reserve0: u128, reserve1: u128) -> bool;
}

#[starknet::contract]
mod Pair {
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::get_block_timestamp;
    use starknet::ContractAddress;
    use integer::u256_sqrt;
    use cmp::min;

    use unicairo_v2::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use unicairo_v2::pair::interface::IPair;

    use unicairo_v2::erc20::erc20::erc20 as erc20_component;
    use unicairo_v2::reentrancy_guard::reentrancy_guard::reentrancy_guard as reentrancy_guard_component;

    component!(path: erc20_component, storage: erc20, event: ERC20Event);
    component!(path: reentrancy_guard_component, storage: reentrancy_guard, event: ReentrancyGuardEvent);

    #[abi(embed_v0)]
    impl ERC20 = erc20_component::ERC20Impl<ContractState>;

    impl ERC20Internal = erc20_component::ERC20InternalImpl<ContractState>;
    impl ReentrancyGuardInternal = reentrancy_guard_component::ReentrancyGuardInternalImpl<ContractState>;

    const MINIMUM_LIQUIDITY: u256 = 10_000;

    #[storage]
    struct Storage {
        _factory: ContractAddress,
        _token0: IERC20Dispatcher,
        _token1: IERC20Dispatcher,
        _reserve0: u128,
        _reserve1: u128,
        _block_timestamp_last: u64,
        _price0_cumulative_last: u256,
        _price1_cumulative_last: u256,
        _k_last: u256,
        #[substorage(v0)]
        erc20: erc20_component::Storage,
        #[substorage(v0)]
        reentrancy_guard: reentrancy_guard_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Swap: Swap,
        Sync: Sync,
        Mint: Mint,
        Burn: Burn,
        ERC20Event: erc20_component::Event,
        ReentrancyGuardEvent: reentrancy_guard_component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Swap {
        #[key]
        sender: ContractAddress,
        amount0_in: u256,
        amount1_in: u256,
        amount0_out: u256,
        amount1_out: u256,
        #[key]
        to: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct Sync {
        reserve0: u128,
        reserve1: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct Mint {
        #[key]
        sender: ContractAddress,
        amount0: u256,
        amount1: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Burn {
        #[key]
        sender: ContractAddress,
        amount0: u256,
        amount1: u256,
        #[key]
        to: ContractAddress,
    }

    mod Errors {
        const NOT_FACTORY: felt252 = 'Pair: Caller is not factory';
        const INSUFFICIENT_LIQUIDITY: felt252 = 'Pair: Insuficient liquidity';
        const INSUFFICIENT_OUTPUT: felt252 = 'Pair: Insuficient output';
        const INVALID_TO: felt252 = 'Pair: Invalid to';
        const INSUFFICIENT_INPUT: felt252 = 'Pair: Insufficient input';
        const K: felt252 = 'Pair: K';
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        let factory = get_caller_address();

        self._factory.write(factory);
    }

    fn _uq_encode(y: u128) -> u256 {
        y.into() * 0x100000000000000000000000000000000_u256
    }

    fn _uq_div(x: u256, y: u128) -> u256 {
        x / y.into()
    }

    impl PairInternalImpl of super::PairInternalTrait<ContractState> {
        fn _update(ref self: ContractState, balance0: u128, balance1: u128, reserve0: u128, reserve1: u128) {
            let timestamp = get_block_timestamp();
            let time_elapsed = timestamp - self._block_timestamp_last.read();

            if time_elapsed > 0 && reserve0 != 0 && reserve1 != 0 {
                self._price0_cumulative_last.write(
                    self._price0_cumulative_last.read() + _uq_div(_uq_encode(reserve1), reserve0).into() * time_elapsed.into()
                );
                self._price1_cumulative_last.write(
                    self._price1_cumulative_last.read() + _uq_div(_uq_encode(reserve0), reserve1).into() * time_elapsed.into()
                );
            }

            self._reserve0.write(balance0);
            self._reserve1.write(balance1);
            self._block_timestamp_last.write(timestamp);

            self.emit(Sync { reserve0, reserve1 });
        }

        fn _mint_fee(ref self: ContractState, reserve0: u128, reserve1: u128) -> bool {
            true // TODO
        }
    }

    #[external(v0)]
    impl PairImpl of IPair<ContractState> {
        fn initialize(ref self: ContractState, token0: ContractAddress, token1: ContractAddress) {
            let caller = get_caller_address();

            assert(caller == self._factory.read(), Errors::NOT_FACTORY);

            self._token0.write(IERC20Dispatcher { contract_address: token0 });
            self._token1.write(IERC20Dispatcher { contract_address: token1 });
        }

        fn MINIMUM_LIQUIDITY(self: @ContractState) -> u256 {
            MINIMUM_LIQUIDITY
        }

        fn factory(self: @ContractState) -> ContractAddress {
            self._factory.read()
        }

        fn token0(self: @ContractState) -> IERC20Dispatcher {
            self._token0.read()
        }

        fn token1(self: @ContractState) -> IERC20Dispatcher {
            self._token1.read()
        }

        fn get_reserves(self: @ContractState) -> (u128, u128, u64) {
            (self._reserve0.read(), self._reserve1.read(), self._block_timestamp_last.read())
        }

        fn price0_cumulative_last(self: @ContractState) -> u256 {
            self._price0_cumulative_last.read()
        }

        fn price1_cumulative_last(self: @ContractState) -> u256 {
            self._price1_cumulative_last.read()
        }

        fn k_last(self: @ContractState) -> u256 {
            self._k_last.read()
        }

        fn mint(ref self: ContractState, to: ContractAddress) -> u256 {
            self.reentrancy_guard._lock_start();

            let this = get_contract_address();

            let reserve0 = self._reserve0.read();
            let reserve1 = self._reserve1.read();

            let balance0 = self._token0.read().balance_of(this);
            let balance1 = self._token1.read().balance_of(this);

            let amount0 = balance0 - reserve0.into();
            let amount1 = balance1 - reserve1.into();

            let fee_on = self._mint_fee(reserve0, reserve1);
            let total_supply = self.erc20._total_supply.read();

            let liquidity = if total_supply == 0 {
                let val = u256_sqrt(amount0 * amount1).into() - MINIMUM_LIQUIDITY;
                ERC20Internal::_mint(ref self.erc20, Zeroable::zero(), MINIMUM_LIQUIDITY);
                val
            }
            else {
                min((amount0 * total_supply) / reserve0.into(), (amount1 * total_supply) / reserve1.into())
            };

            assert(liquidity > 0, Errors::INSUFFICIENT_LIQUIDITY);

            ERC20Internal::_mint(ref self.erc20, to, liquidity);
            self._update(balance0.try_into().unwrap(), balance1.try_into().unwrap(), reserve0, reserve1);

            if fee_on {
                let reserve0 = self._reserve0.read();
                let reserve1 = self._reserve1.read();

                self._k_last.write((reserve0 * reserve1).into());
            }

            self.emit(Mint { sender: get_caller_address(), amount0, amount1 });

            ReentrancyGuardInternal::_lock_end(ref self.reentrancy_guard);

            liquidity
        }

        fn burn(ref self: ContractState, to: ContractAddress) -> (u256, u256) {
            ReentrancyGuardInternal::_lock_start(ref self.reentrancy_guard);

            let this = get_contract_address();

            let reserve0 = self._reserve0.read();
            let reserve1 = self._reserve1.read();

            let token0 = self._token0.read();
            let token1 = self._token1.read();

            let balance0 = self._token0.read().balance_of(this);
            let balance1 = self._token1.read().balance_of(this);

            let liquidity = self.erc20._balances.read(this);
            
            let fee_on = self._mint_fee(reserve0, reserve1);
            let total_supply = self.erc20._total_supply.read();

            let amount0 = (liquidity * balance0) / total_supply;
            let amount1 = (liquidity * balance1) / total_supply;

            assert(amount0 > 0 && amount1 > 0, Errors::INSUFFICIENT_LIQUIDITY);

            ERC20Internal::_burn(ref self.erc20, this, liquidity);
            
            token0.transfer(to, amount0);
            token1.transfer(to, amount1);

            let balance0 = self._token0.read().balance_of(this);
            let balance1 = self._token1.read().balance_of(this);

            self._update(balance0.try_into().unwrap(), balance1.try_into().unwrap(), reserve0, reserve1);
            
            if fee_on {
                let reserve0 = self._reserve0.read();
                let reserve1 = self._reserve1.read();

                self._k_last.write((reserve0 * reserve1).into());
            }

            self.emit(Burn { sender: get_caller_address(), amount0, amount1, to });

            ReentrancyGuardInternal::_lock_end(ref self.reentrancy_guard);

            (amount0, amount1)
        }

        fn swap(ref self: ContractState, amount0_out: u256, amount1_out: u256, to: ContractAddress) {
            ReentrancyGuardInternal::_lock_start(ref self.reentrancy_guard);

            let this = get_contract_address();

            let reserve0 = self._reserve0.read();
            let reserve1 = self._reserve1.read();

            assert(amount0_out > 0 || amount1_out > 0, Errors::INSUFFICIENT_OUTPUT);
            assert(amount0_out < reserve0.into() && amount1_out < reserve1.into(), Errors::INSUFFICIENT_LIQUIDITY);

            let token0 = self._token0.read();
            let token1 = self._token1.read();

            assert(to != token0.contract_address && to != token1.contract_address, Errors::INVALID_TO);

            if amount0_out > 0 {
                token0.transfer(to, amount0_out);
            }

            if amount1_out > 0 {
                token1.transfer(to, amount1_out);
            }

            let balance0 = self._token0.read().balance_of(this);
            let balance1 = self._token1.read().balance_of(this);

            let amount0_in = if balance0 > reserve0.into() - amount0_out {
                balance0 - (reserve0.into() - amount0_out)
            }
            else {
                0
            };

            let amount1_in = if balance1 > reserve1.into() - amount1_out {
                balance1 - (reserve1.into() - amount1_out)
            }
            else {
                0
            };

            assert(amount0_in > 0 || amount1_in > 0, Errors::INSUFFICIENT_INPUT);

            let balance0_adjusted = balance0 * 1000 - amount0_in * 3;
            let balance1_adjusted = balance1 * 1000 - amount1_in * 3;

            assert(balance0_adjusted * balance1_adjusted >= reserve0.into() * reserve1.into() * 1000000, Errors::K);

            self._update(balance0.try_into().unwrap(), balance1.try_into().unwrap(), reserve0, reserve1);
            self.emit(Swap { sender: get_caller_address(), amount0_in, amount1_in, amount0_out, amount1_out, to });

            ReentrancyGuardInternal::_lock_end(ref self.reentrancy_guard);
        }

        fn skim(ref self: ContractState, to: ContractAddress) {
            ReentrancyGuardInternal::_lock_start(ref self.reentrancy_guard);

            let this = get_caller_address();

            let token0 = self._token0.read();
            let token1 = self._token1.read();

            let reserve0 = self._reserve0.read();
            let reserve1 = self._reserve1.read();

            token0.transfer(to, token0.balance_of(this) - reserve0.into());
            token0.transfer(to, token1.balance_of(this) - reserve1.into());

            ReentrancyGuardInternal::_lock_end(ref self.reentrancy_guard);
        }

        fn sync(ref self: ContractState) {
            ReentrancyGuardInternal::_lock_start(ref self.reentrancy_guard);

            let this = get_caller_address();

            let token1 = self._token1.read();
            let token0 = self._token0.read();

            let reserve0 = self._reserve0.read();
            let reserve1 = self._reserve1.read();

            let balance0 = self._token0.read().balance_of(this);
            let balance1 = self._token1.read().balance_of(this);

            self._update(balance0.try_into().unwrap(), balance1.try_into().unwrap(), reserve0, reserve1);

            ReentrancyGuardInternal::_lock_end(ref self.reentrancy_guard);
        }
    }
}