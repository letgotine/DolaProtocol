module lending::logic {
    use std::vector;

    use dola_types::types::{DolaAddress, decode_dola_address, encode_dola_address};
    use lending::math::{Self, calculate_compounded_interest, calculate_linear_interest};
    use lending::rates;
    use lending::scaled_balance::{Self, balance_of};
    use lending::storage::{Self, StorageCap, Storage, get_liquidity_index, get_user_collaterals, get_user_scaled_otoken, get_user_loans, get_user_scaled_dtoken, add_user_collateral, add_user_loan, get_otoken_scaled_total_supply, get_borrow_index, get_dtoken_scaled_total_supply, get_app_id, remove_user_collateral, remove_user_loan};
    use oracle::oracle::{get_token_price, PriceOracle, get_timestamp};
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use serde::serde::{deserialize_u64, deserialize_u8, vector_slice, deserialize_u16, serialize_u64, serialize_u16, serialize_vector, serialize_u8};
    use sui::math::pow;

    const RAY: u64 = 100000000;

    const ECOLLATERAL_AS_LOAN: u64 = 0;

    const ENOT_HEALTH: u64 = 1;

    const EIS_HEALTH: u64 = 2;

    const ENOT_COLLATERAL: u64 = 3;

    const ENOT_LOAN: u64 = 4;

    const ENOT_ENOUGH_OTOKEN: u64 = 5;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 6;

    const EINVALID_LENGTH: u64 = 7;

    public fun execute_liquidate(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        collateral: u16,
        loan_token: u16,
        repay_debt: u64,
    ): u64 {
        update_state(cap, storage, oracle, loan_token);
        update_state(cap, storage, oracle, collateral);
        assert!(is_collateral(storage, dola_user_id, collateral), ENOT_COLLATERAL);
        assert!(is_loan(storage, dola_user_id, loan_token), ENOT_LOAN);
        assert!(!check_health_factor(storage, oracle, dola_user_id), EIS_HEALTH);
        let liquidated_debt = repay_debt;
        let liquidated_debt_val = calculate_value(oracle, loan_token, liquidated_debt);
        let (collateral_price, decimal) = get_token_price(oracle, collateral);
        // todo: fix calculation
        let collateral_amount = liquidated_debt_val * pow(10, decimal) / collateral_price;
        burn_dtoken(cap, storage, dola_user_id, loan_token, liquidated_debt);
        burn_otoken(cap, storage, dola_user_id, collateral, collateral_amount);
        update_interest_rate(cap, pool_manager_info, storage, collateral);
        update_interest_rate(cap, pool_manager_info, storage, loan_token);
        collateral_amount
    }

    public fun execute_supply(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        assert!(!is_loan(storage, dola_user_id, dola_pool_id), ENOT_LOAN);
        update_state(cap, storage, oracle, dola_pool_id);
        mint_otoken(cap, storage, dola_user_id, dola_pool_id, token_amount);
        update_interest_rate(cap, pool_manager_info, storage, dola_pool_id);
        if (!is_collateral(storage, dola_user_id, dola_pool_id)) {
            add_user_collateral(cap, storage, dola_user_id, dola_pool_id);
        }
    }


    public fun execute_withdraw(
        cap: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        pool_manager_info: &PoolManagerInfo,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        update_state(cap, storage, oracle, dola_pool_id);
        // check otoken amount
        let otoken_amount = user_collateral_balance(storage, dola_user_id, dola_pool_id);
        assert!(token_amount <= otoken_amount, ENOT_ENOUGH_OTOKEN);
        burn_otoken(cap, storage, dola_user_id, dola_pool_id, token_amount);

        update_interest_rate(cap, pool_manager_info, storage, dola_pool_id);

        assert!(check_health_factor(storage, oracle, dola_user_id), ENOT_HEALTH);
        if (token_amount == otoken_amount) {
            remove_user_collateral(cap, storage, dola_user_id, dola_pool_id);
        }
    }

    public fun execute_borrow(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        update_state(cap, storage, oracle, dola_pool_id);

        assert!(!is_collateral(storage, dola_user_id, dola_pool_id), ECOLLATERAL_AS_LOAN);
        if (!is_loan(storage, dola_user_id, dola_pool_id)) {
            add_user_loan(cap, storage, dola_user_id, dola_pool_id);
        };
        mint_dtoken(cap, storage, dola_user_id, dola_pool_id, token_amount);

        let liquidity = pool_manager::get_app_liquidity_by_pool_id(
            pool_manager_info,
            dola_pool_id,
            get_app_id(storage)
        );
        assert!((token_amount as u128) <= liquidity, ENOT_ENOUGH_LIQUIDITY);
        assert!(check_health_factor(storage, oracle, dola_user_id), ENOT_HEALTH);
        update_interest_rate(cap, pool_manager_info, storage, dola_pool_id);
    }

    public fun execute_repay(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        update_state(cap, storage, oracle, dola_pool_id);
        let debt = user_loan_balance(storage, dola_user_id, dola_pool_id);
        let repay_debt = if (debt > token_amount) { token_amount } else { debt };
        burn_dtoken(cap, storage, dola_user_id, dola_pool_id, repay_debt);
        update_interest_rate(cap, pool_manager_info, storage, dola_pool_id);
        if (token_amount == repay_debt) {
            remove_user_loan(cap, storage, dola_user_id, dola_pool_id);
        }
    }

    public fun check_health_factor(storage: &mut Storage, oracle: &mut PriceOracle, dola_user_id: u64): bool {
        let collateral_value = user_total_collateral_value(storage, oracle, dola_user_id);
        let loan_value = user_total_loan_value(storage, oracle, dola_user_id);
        collateral_value >= loan_value
    }

    public fun is_collateral(storage: &mut Storage, dola_user_id: u64, dola_pool_id: u16): bool {
        let collaterals = get_user_collaterals(storage, dola_user_id);
        vector::contains(&collaterals, &dola_pool_id)
    }

    public fun is_loan(storage: &mut Storage, dola_user_id: u64, dola_pool_id: u16): bool {
        let loans = get_user_loans(storage, dola_user_id);
        vector::contains(&loans, &dola_pool_id)
    }

    public fun encode_app_payload(
        call_type: u8,
        amount: u64,
        receiver: DolaAddress,
        liquidate_user_id: u64
    ): vector<u8> {
        let payload = vector::empty<u8>();
        serialize_u64(&mut payload, amount);
        let receiver = encode_dola_address(receiver);
        serialize_u16(&mut payload, (vector::length(&receiver) as u16));
        serialize_vector(&mut payload, receiver);
        serialize_u64(&mut payload, liquidate_user_id);
        serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_app_payload(app_payload: vector<u8>): (u8, u64, DolaAddress, u64) {
        let index = 0;
        let data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let receive_length = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = (receive_length as u64);
        let receiver = decode_dola_address(vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let liquidate_user_id = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        assert!(index == vector::length(&app_payload), EINVALID_LENGTH);

        (call_type, amount, receiver, liquidate_user_id)
    }

    public fun user_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u64 {
        let balance = user_collateral_balance(storage, dola_user_id, dola_pool_id);
        let (price, decimal) = get_token_price(oracle, dola_pool_id);
        (((balance as u128) * (price as u128) / (pow(10, decimal) as u128)) as u64)
    }

    public fun user_collateral_balance(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u64 {
        let scaled_balance = get_user_scaled_otoken(storage, dola_user_id, dola_pool_id);
        let current_index = get_liquidity_index(storage, dola_pool_id);
        balance_of(scaled_balance, current_index)
    }

    public fun calculate_value(oracle: &mut PriceOracle, dola_pool_id: u16, amount: u64): u64 {
        let (price, decimal) = get_token_price(oracle, dola_pool_id);
        (((amount as u128) * (price as u128) / (pow(10, decimal) as u128)) as u64)
    }

    public fun user_loan_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u64 {
        let balance = user_loan_balance(storage, dola_user_id, dola_pool_id);
        let (price, decimal) = get_token_price(oracle, dola_pool_id);
        (((balance as u128) * (price as u128) / (pow(10, decimal) as u128)) as u64)
    }

    public fun user_loan_balance(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u64 {
        let scaled_balance = get_user_scaled_dtoken(storage, dola_user_id, dola_pool_id);
        let current_index = get_liquidity_index(storage, dola_pool_id);
        balance_of(scaled_balance, current_index)
    }


    public fun user_total_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    ): u64 {
        let collaterals = get_user_collaterals(storage, dola_user_id);
        let length = vector::length(&collaterals);
        let value = 0;
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            // todo: fix token decimal
            let collateral_value = user_collateral_value(storage, oracle, dola_user_id, *collateral);
            value = value + collateral_value;
            i = i + 1;
        };
        value
    }

    public fun user_total_loan_value(storage: &mut Storage, oracle: &mut PriceOracle, dola_user_id: u64): u64 {
        let loans = get_user_collaterals(storage, dola_user_id);
        let length = vector::length(&loans);
        let value = 0;
        let i = 0;
        while (i < length) {
            let loan = vector::borrow(&loans, i);
            // todo: fix token decimal
            let loan_value = user_loan_value(storage, oracle, dola_user_id, *loan);
            value = value + loan_value;
            i = i + 1;
        };
        value
    }

    public fun total_otoken_supply(storage: &mut Storage, dola_pool_id: u16): u128 {
        let scaled_total_otoken_supply = get_otoken_scaled_total_supply(storage, dola_pool_id);
        let current_index = get_liquidity_index(storage, dola_pool_id);
        scaled_total_otoken_supply * (current_index as u128) / (RAY as u128)
    }

    public fun total_dtoken_supply(storage: &mut Storage, dola_pool_id: u16): u128 {
        let scaled_total_dtoken_supply = get_dtoken_scaled_total_supply(storage, dola_pool_id);
        let current_index = get_borrow_index(storage, dola_pool_id);
        scaled_total_dtoken_supply * (current_index as u128) / (RAY as u128)
    }

    public fun mint_otoken(
        cap: &StorageCap, // todo! Where manage this?
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(token_amount, get_liquidity_index(storage, dola_pool_id));
        storage::mint_otoken_scaled(
            cap,
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    public fun burn_otoken(
        cap: &StorageCap,
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::burn_scaled(token_amount, get_liquidity_index(storage, dola_pool_id));
        storage::burn_otoken_scaled(
            cap,
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    public fun mint_dtoken(
        cap: &StorageCap,
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(token_amount, get_liquidity_index(storage, dola_pool_id));
        storage::mint_dtoken_scaled(
            cap,
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    public fun burn_dtoken(
        cap: &StorageCap,
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::burn_scaled(token_amount, get_liquidity_index(storage, dola_pool_id));
        storage::burn_dtoken_scaled(
            cap,
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    public fun update_state(
        cap: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_pool_id: u16,
    ) {
        // todo: use sui timestamp
        let current_timestamp = get_timestamp(oracle);

        let last_update_timestamp = storage::get_last_update_timestamp(storage, dola_pool_id);
        let dtoken_scaled_total_supply = storage::get_dtoken_scaled_total_supply(storage, dola_pool_id);
        let current_borrow_index = storage::get_borrow_index(storage, dola_pool_id);
        let current_liquidity_index = storage::get_liquidity_index(storage, dola_pool_id);

        let treasury_factor = storage::get_treasury_factor(storage, dola_pool_id);

        let new_borrow_index = math::ray_mul(calculate_compounded_interest(
            current_timestamp,
            last_update_timestamp,
            storage::get_borrow_rate(storage, dola_pool_id)
        ), current_borrow_index) ;

        let new_liquidity_index = math::ray_mul(calculate_linear_interest(
            current_timestamp,
            last_update_timestamp,
            storage::get_liquidity_rate(storage, dola_pool_id)
        ), current_liquidity_index);

        let mint_to_treasury = ((dtoken_scaled_total_supply *
            ((new_borrow_index - current_borrow_index) as u128) /
            (RAY as u128) * (treasury_factor as u128) / (RAY as u128)) as u64);
        storage::update_state(cap, storage, dola_pool_id, new_borrow_index, new_liquidity_index, mint_to_treasury);
    }

    public fun update_interest_rate(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        dola_pool_id: u16,
    ) {
        let liquidity = pool_manager::get_app_liquidity_by_pool_id(
            pool_manager_info,
            dola_pool_id,
            get_app_id(storage)
        );
        let borrow_rate = rates::calculate_borrow_rate(storage, dola_pool_id, liquidity);
        let liquidity_rate = rates::calculate_liquidity_rate(storage, dola_pool_id, borrow_rate, liquidity);
        storage::update_interest_rate(cap, storage, dola_pool_id, borrow_rate, liquidity_rate);
    }
}
