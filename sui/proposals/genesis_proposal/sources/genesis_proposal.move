module genesis_proposal::genesis_proposal {
    use std::ascii::string;
    use std::option;

    use app_manager::app_manager::{Self, TotalAppInfo};
    use dola_portal::portal::DolaPortal;
    use dola_types::types::create_dola_address;
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use lending_core::lending_wormhole_adapter::WormholeAdapater;
    use lending_core::storage::Storage;
    use omnipool::pool;
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use sui::tx_context::TxContext;
    use user_manager::user_manager::{Self, UserManagerInfo};
    use wormhole::state::State;
    use wormhole_bridge::bridge_core::{Self, CoreState};
    use wormhole_bridge::bridge_pool::{Self, PoolState};

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext) {
        governance_v1::create_proposal<Certificate>(governance_info, Certificate {}, ctx)
    }

    public entry fun vote_init_bridge_cap(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        state: &mut State,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            bridge_core::initialize_wormhole_with_governance(&governance_cap, state, ctx);
            bridge_pool::initialize_wormhole_with_governance(&governance_cap, state, ctx);
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_init_lending_storage(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        storage: &mut Storage,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            let app_cap = app_manager::register_cap_with_governance(&governance_cap, total_app_info, ctx);
            lending_core::storage::transfer_app_cap(storage, app_cap);
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }


    public entry fun vote_init_lending_wormhole_adapter(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        wormhole_adapater: &mut WormholeAdapater,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            let storage_cap = lending_core::storage::register_cap_with_governance(&governance_cap);
            lending_core::lending_wormhole_adapter::transfer_storage_cap(wormhole_adapater, storage_cap);
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_init_lending_portal(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        lending_portal: &mut DolaPortal,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            let pool_cap = pool::register_cap(&governance_cap, ctx);
            let storage_cap = lending_core::storage::register_cap_with_governance(&governance_cap);
            let pool_manager_cap = pool_manager::pool_manager::register_cap_with_governance(&governance_cap);
            let user_manager_cap = user_manager::user_manager::register_cap_with_governance(&governance_cap);
            dola_portal::portal::transfer_pool_cap(lending_portal, pool_cap);
            dola_portal::portal::transfer_storage_cap(lending_portal, storage_cap);
            dola_portal::portal::transfer_pool_manager_cap(lending_portal, pool_manager_cap);
            dola_portal::portal::transfer_user_manager_cap(lending_portal, user_manager_cap);
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_register_evm_chain_id(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        user_manager: &mut UserManagerInfo,
        evm_chain_id: u16,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            let user_manager_cap = user_manager::register_cap_with_governance(&governance_cap);
            // todo: chain id should be fixed, initializing multiple evm_chain_id according to the actual situation
            user_manager::register_evm_chain_id(&user_manager_cap, user_manager, evm_chain_id);
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_register_core_remote_bridge(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        core_state: &mut CoreState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            bridge_core::register_remote_bridge(&governance_cap, core_state, emitter_chain_id, emitter_address, ctx);
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_register_pool_remote_bridge(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        pool_state: &mut PoolState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            bridge_pool::register_remote_bridge(&governance_cap, pool_state, emitter_chain_id, emitter_address, ctx);
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }


    public entry fun vote_register_new_pool(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_address: vector<u8>,
        pool_dola_chain_id: u16,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            let pool_manager_cap = pool_manager::register_cap_with_governance(&governance_cap);
            let pool = create_dola_address(pool_dola_chain_id, pool_dola_address);

            pool_manager::register_pool(
                &pool_manager_cap,
                pool_manager_info,
                pool,
                string(dola_pool_name),
                dola_pool_id,
                0,
                ctx
            );
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_register_new_reserve(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        oracle: &mut PriceOracle,
        dola_pool_id: u16,
        treasury: u64,
        treasury_factor: u256,
        collateral_coefficient: u256,
        borrow_coefficient: u256,
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256,
        storage: &mut Storage,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            let storage_cap = lending_core::storage::register_cap_with_governance(&governance_cap);
            lending_core::storage::register_new_reserve(
                &storage_cap,
                storage,
                oracle,
                dola_pool_id,
                treasury,
                treasury_factor,
                collateral_coefficient,
                borrow_coefficient,
                base_borrow_rate,
                borrow_rate_slope1,
                borrow_rate_slope2,
                optimal_utilization,
                ctx
            );
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }
}