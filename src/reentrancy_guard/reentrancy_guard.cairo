trait ReentrancyGuardInternal<TContractState> {
    fn _lock_start(ref self: reentrancy_guard::ComponentState<TContractState>);
    fn _lock_end(ref self: reentrancy_guard::ComponentState<TContractState>);
}

#[starknet::component]
mod reentrancy_guard {
    #[storage]
    struct Storage {
        _lock: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    mod Errors {
        const REENTRANT_CALL: felt252 = 'Reentrant call';
    }

    impl ReentrancyGuardInternalImpl<
        TContractState, +HasComponent<TContractState>
    > of super::ReentrancyGuardInternal<TContractState> {
        fn _lock_start(ref self: ComponentState<TContractState>) {
            assert(!self._lock.read(), Errors::REENTRANT_CALL);
            self._lock.write(true);
        }

        fn _lock_end(ref self: ComponentState<TContractState>) {
            self._lock.write(false);
        }
    }
}
