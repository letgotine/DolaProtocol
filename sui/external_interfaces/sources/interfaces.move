/// Unified external call interface to get data
/// by simulating calls to trigger events.
module external_interfaces::interfaces {
    use std::ascii::{String, string, into_bytes};
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{create_dola_address};
    use lending::logic::{user_loan_balance, user_loan_value, user_collateral_balance, user_collateral_value, total_dtoken_supply, user_total_collateral_value, user_total_loan_value, is_collateral};
    use lending::rates::calculate_utilization;
    use lending::storage::{Storage, get_user_collaterals, get_user_loans, get_borrow_rate, get_liquidity_rate, get_app_id};
    use oracle::oracle::{PriceOracle, get_token_price};
    use pool_manager::pool_manager::{token_liquidity, PoolManagerInfo, get_app_liquidity, get_pool_name_by_id};
    use sui::event::emit;
    use sui::math::{pow, min};
    use user_manager::user_manager::{Self, UserManagerInfo};

    const RAY: u64 = 100000000;

    struct PoolInfo has store, drop {}

    struct TokenLiquidityInfo has copy, drop {
        dola_pool_id: u16,
        token_liquidity: u64,
    }

    struct AppLiquidityInfo has copy, drop {
        app_id: u16,
        dola_pool_id: u16,
        token_liquidity: u128,
    }

    struct LendingReserveInfo has copy, drop {
        dola_pool_id: u16,
        borrow_apy: u64,
        supply_apy: u64,
        reserve: u128,
        debt: u128,
        utilization_rate: u64
    }

    struct UserLendingInfo has copy, drop {
        collateral_infos: vector<UserCollateralInfo>,
        total_collateral_value: u64,
        debt_infos: vector<UserDebtInfo>,
        total_debt_value: u64
    }

    struct UserCollateralInfo has copy, drop {
        dola_pool_id: u16,
        collateral_amount: u64,
        collateral_value: u64
    }

    struct UserDebtInfo has copy, drop {
        dola_pool_id: u16,
        debt_amount: u64,
        debt_value: u64
    }

    struct UserAllowedBorrow has copy, drop {
        borrow_token: vector<u8>,
        borrow_amount: u64,
        reason: Option<String>
    }

    struct DolaUserId has copy, drop {
        dola_user_id: u64
    }

    public entry fun get_dola_token_liquidity(pool_manager_info: &mut PoolManagerInfo, dola_pool_id: u16) {
        let token_liquidity = token_liquidity(pool_manager_info, dola_pool_id);
        emit(TokenLiquidityInfo {
            dola_pool_id,
            token_liquidity
        })
    }

    public entry fun get_dola_user_id(user_manager_info: &mut UserManagerInfo, dola_chain_id: u16, user: vector<u8>) {
        let dola_address = create_dola_address(dola_chain_id, user);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, dola_address);
        emit(DolaUserId {
            dola_user_id
        })
    }

    public entry fun get_app_token_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        app_id: u16,
        dola_pool_id: u16
    ) {
        let token_liquidity = get_app_liquidity(pool_manager_info, dola_pool_id, app_id);
        emit(AppLiquidityInfo {
            app_id,
            dola_pool_id,
            token_liquidity
        })
    }

    public entry fun get_user_token_debt(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_manager_info: &mut UserManagerInfo,
        user_address: vector<u8>,
        dola_chain_id: u16,
        dola_pool_id: u16
    ) {
        let dola_user_address = create_dola_address(dola_chain_id, user_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, dola_user_address);
        let debt_amount = user_loan_balance(storage, dola_user_id, dola_pool_id);
        let debt_value = user_loan_value(storage, oracle, dola_user_id, dola_pool_id);
        emit(UserDebtInfo {
            dola_pool_id,
            debt_amount,
            debt_value
        })
    }

    public entry fun get_user_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_manager_info: &mut UserManagerInfo,
        user_address: vector<u8>,
        dola_chain_id: u16,
        dola_pool_id: u16
    ) {
        let dola_user_address = create_dola_address(dola_chain_id, user_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, dola_user_address);
        let collateral_amount = user_collateral_balance(storage, dola_user_id, dola_pool_id);
        let collateral_value = user_collateral_value(storage, oracle, dola_user_id, dola_pool_id);
        emit(UserCollateralInfo {
            dola_pool_id,
            collateral_amount,
            collateral_value
        })
    }

    public entry fun get_user_lending_info(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_manager_info: &mut UserManagerInfo,
        user_address: vector<u8>,
        dola_chain_id: u16
    ) {
        let dola_user_address = create_dola_address(dola_chain_id, user_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, dola_user_address);
        let collateral_infos = vector::empty<UserCollateralInfo>();
        let collaterals = get_user_collaterals(storage, dola_user_id);
        let total_collateral_value = 0;
        let debt_infos = vector::empty<UserDebtInfo>();
        let loans = get_user_loans(storage, dola_user_id);
        let total_debt_value = 0;

        let length = vector::length(&collaterals);
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            let collateral_amount = user_collateral_balance(storage, dola_user_id, *collateral);
            let collateral_value = user_collateral_value(storage, oracle, dola_user_id, *collateral);
            vector::push_back(&mut collateral_infos, UserCollateralInfo {
                dola_pool_id: *collateral,
                collateral_amount,
                collateral_value
            });
            total_collateral_value = total_collateral_value + collateral_value;
            i = i + 1;
        };

        length = vector::length(&loans);
        i = 0;
        while (i < length) {
            let loan = vector::borrow(&loans, i);
            let debt_amount = user_loan_balance(storage, dola_user_id, *loan);
            let debt_value = user_loan_value(storage, oracle, dola_user_id, *loan);
            vector::push_back(&mut debt_infos, UserDebtInfo {
                dola_pool_id: *loan,
                debt_amount,
                debt_value
            });
            total_debt_value = total_debt_value + debt_value;
            i = i + 1;
        };

        emit(UserLendingInfo {
            collateral_infos,
            total_collateral_value,
            debt_infos,
            total_debt_value
        })
    }

    public entry fun get_reserve_info(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        dola_pool_id: u16
    ) {
        let borrow_rate = get_borrow_rate(storage, dola_pool_id);
        let borrow_apy = borrow_rate * 10000 / RAY;
        let liquidity_rate = get_liquidity_rate(storage, dola_pool_id);
        let supply_apy = liquidity_rate * 10000 / RAY;
        let debt = total_dtoken_supply(storage, dola_pool_id);
        let reserve = get_app_liquidity(pool_manager_info, dola_pool_id, get_app_id(storage));
        let utilization = calculate_utilization(storage, dola_pool_id, reserve);
        let utilization_rate = utilization * 10000 / RAY;
        emit(LendingReserveInfo {
            dola_pool_id,
            borrow_apy,
            supply_apy,
            reserve,
            debt,
            utilization_rate
        })
    }

    public entry fun get_user_allowed_borrow(
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        borrow_pool_id: u16,
        user_address: vector<u8>,
        dola_chain_id: u16
    ) {
        let dola_user_address = create_dola_address(dola_chain_id, user_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, dola_user_address);
        let borrow_token = into_bytes(get_pool_name_by_id(pool_manager_info, borrow_pool_id));
        if (is_collateral(storage, dola_user_id, borrow_pool_id)) {
            emit(UserAllowedBorrow {
                borrow_token,
                borrow_amount: 0,
                reason: option::some(string(b"Borrowed token is collateral"))
            });
            return
        };
        let user_total_collateral_value = user_total_collateral_value(storage, oracle, dola_user_id);
        let user_total_loan_value = user_total_loan_value(storage, oracle, dola_user_id);
        let (price, decimal) = get_token_price(oracle, borrow_pool_id);
        let can_borrow_value = user_total_collateral_value - user_total_loan_value;
        let borrow_amount = can_borrow_value * pow(10, decimal) / price;
        let reserve = get_app_liquidity(pool_manager_info, borrow_pool_id, get_app_id(storage));
        if (reserve == 0) {
            emit(UserAllowedBorrow {
                borrow_token,
                borrow_amount: 0,
                reason: option::some(string(b"Not enough liquidity to borrow"))
            });
            return
        };
        borrow_amount = min(borrow_amount, (reserve as u64));
        emit(UserAllowedBorrow {
            borrow_token,
            borrow_amount,
            reason: option::none()
        })
    }
}