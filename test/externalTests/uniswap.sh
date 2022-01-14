#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# This file is part of solidity.
#
# solidity is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# solidity is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with solidity.  If not, see <http://www.gnu.org/licenses/>
#
# (c) 2022 solidity contributors.
#------------------------------------------------------------------------------

set -e

source scripts/common.sh
source test/externalTests/common.sh

verify_input "$@"
BINARY_TYPE="$1"
BINARY_PATH="$2"

function compile_fn { yarn compile; }
function test_fn { yarn test; }

function uniswap_test
{
    local repo="https://github.com/Uniswap/v3-core"
    local ref_type=branch
    local ref=main
    local config_file="hardhat.config.ts"
    local config_var=config

    local compile_only_presets=()
    local settings_presets=(
        "${compile_only_presets[@]}"
        #ir-no-optimize           # Compilation fails with: "YulException: Variable ret_0 is 1 slot(s) too deep inside the stack."
        #ir-optimize-evm-only     # Compilation fails with: "YulException: Variable ret_0 is 1 slot(s) too deep inside the stack."
        #ir-optimize-evm+yul      # Compilation fails with: "YulException: Variable var_slot0Start_mpos is 1 too deep in the stack"
        legacy-no-optimize
        legacy-optimize-evm-only
        legacy-optimize-evm+yul
    )

    [[ $SELECTED_PRESETS != "" ]] || SELECTED_PRESETS=$(circleci_select_steps_multiarg "${settings_presets[@]}")
    print_presets_or_exit "$SELECTED_PRESETS"

    setup_solc "$DIR" "$BINARY_TYPE" "$BINARY_PATH"
    download_project "$repo" "$ref_type" "$ref" "$DIR"

    # FIXME: There are quite a few places that won't compile on 0.8.x without explicit conversions:
    sed -i 's|uint256(MAX_TICK)|uint256(int256(MAX_TICK))|g' contracts/libraries/TickMath.sol
    sed -i 's|uint8(tick % 256)|uint8(uint24(tick % 256))|g' contracts/libraries/TickBitmap.sol
    sed -i 's|int24(bitPos - BitMath\.mostSignificantBit(masked))|int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))|g' contracts/libraries/TickBitmap.sol
    sed -i 's|int24(BitMath\.leastSignificantBit(masked) - bitPos)|int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))|g' contracts/libraries/TickBitmap.sol
    sed -i 's|int24(bitPos))|int24(uint24(bitPos)))|g' contracts/libraries/TickBitmap.sol
    sed -i 's|int24(type(uint8)\.max - bitPos)|int24(uint24(type(uint8).max - bitPos))|g' contracts/libraries/TickBitmap.sol
    sed -i 's|-denominator & denominator|uint256(-int256(denominator)) \& denominator|g' contracts/libraries/FullMath.sol
    sed -i 's|int56(tick) \* delta|int56(tick) * int56(uint56(delta))|g' contracts/libraries/Oracle.sol
    sed -i 's|uint32 targetDelta = target - beforeOrAt\.blockTimestamp|int56 targetDelta = int56(uint56(target - beforeOrAt.blockTimestamp))|g' contracts/libraries/Oracle.sol
    sed -i 's|((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / observationTimeDelta)|((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / int56(uint56(observationTimeDelta)))|g' contracts/libraries/Oracle.sol
    sed -i 's|) \* targetDelta) / observationTimeDelta|) * uint256(int256(targetDelta))) / uint160(observationTimeDelta)|g' contracts/libraries/Oracle.sol
    sed -i 's|int56 timeWeightedTick = (tickCumulatives\[1\] - tickCumulatives\[0\]) / timeElapsed;|int56 timeWeightedTick = (tickCumulatives\[1\] - tickCumulatives\[0\]) / int56(uint56(timeElapsed));|g' contracts/test/OracleEchidnaTest.sol
    sed -i 's|(tickCumulative1 - tickCumulative0) % timeElapsed|(tickCumulative1 - tickCumulative0) % int56(uint56(timeElapsed))|g' contracts/test/OracleEchidnaTest.sol
    sed -i 's|int56(secondsAgo)|int56(uint56(secondsAgo))|g' contracts/test/OracleEchidnaTest.sol
    sed -i 's|uint256((maxTick - minTick) / tickSpacing)|uint256(int256((maxTick - minTick) / tickSpacing))|g' contracts/test/TickEchidnaTest.sol
    sed -i 's|int256(amount).toInt128()|int256(uint256(amount)).toInt128()|g' contracts/UniswapV3Pool.sol

    # FIXME: This @return causes an ICE: "No return param name given: liquidity"
    # Remove when https://github.com/ethereum/solidity/issues/12528 is fixed.
    sed -i '/@return _liquidity/d' contracts/interfaces/pool/IUniswapV3PoolState.sol

    neutralize_package_json_hooks
    neutralize_package_lock
    name_hardhat_default_export "$config_file" "$config_var"
    force_hardhat_compiler_binary "$config_file" "$BINARY_TYPE" "$BINARY_PATH"
    force_hardhat_compiler_settings "$config_file" "$(first_word "$SELECTED_PRESETS")" "$config_var"
    force_hardhat_unlimited_contract_size "$config_file" "$config_var"
    yarn install

    replace_version_pragmas

    for preset in $SELECTED_PRESETS; do
        hardhat_run_test "$config_file" "$preset" "${compile_only_presets[*]}" compile_fn test_fn "$config_var"
    done
}

external_test Uniswap-V3 uniswap_test
