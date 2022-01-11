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
# (c) 2019 solidity contributors.
#------------------------------------------------------------------------------

set -e

source scripts/common.sh
source test/externalTests/common.sh

verify_input "$@"
BINARY_TYPE="$1"
BINARY_PATH="$2"
SELECTED_PRESETS="$3"

function compile_fn { npm run build; }
function test_fn { npm test; }

function gp2_test
{
    local repo="https://github.com/gnosis/gp-v2-contracts.git"
    local ref_type=branch
    local ref=main
    local config_file="hardhat.config.ts"
    local config_var="config"

    local compile_only_presets=(
        ir-optimize-evm+yul       # Compiles but tests fail. See https://github.com/nomiclabs/hardhat/issues/2115
    )
    local settings_presets=(
        "${compile_only_presets[@]}"
        #ir-no-optimize           # Compilation fails with "YulException: Variable var_amount_1468 is 10 slot(s) too deep inside the stack."
        #ir-no-optimize           # Compilation fails with "YulException: Variable var_offset_3451 is 1 slot(s) too deep inside the stack."
        legacy-no-optimize
        legacy-optimize-evm-only
        legacy-optimize-evm+yul
    )

    [[ $SELECTED_PRESETS != "" ]] || SELECTED_PRESETS=$(circleci_select_steps_multiarg "${settings_presets[@]}")
    print_presets_or_exit "$SELECTED_PRESETS"

    setup_solc "$DIR" "$BINARY_TYPE" "$BINARY_PATH"
    download_project "$repo" "$ref_type" "$ref" "$DIR"
    [[ $BINARY_TYPE == native ]] && replace_global_solc "$BINARY_PATH"

    neutralize_package_lock
    neutralize_package_json_hooks
    name_hardhat_default_export "$config_file" "$config_var"
    force_hardhat_compiler_binary "$config_file" "$BINARY_TYPE" "$BINARY_PATH"
    force_hardhat_compiler_settings "$config_file" "$(first_word "$SELECTED_PRESETS")" "$config_var"
    force_hardhat_unlimited_contract_size "$config_file" "$config_var"
    npm install

    # Some dependencies come with pre-built artifacts. We want to build from scratch.
    rm -r node_modules/@gnosis.pm/safe-contracts/build/

    # FIXME: One of the E2E tests tries to import artifacts from Gnosis Safe. We should rebuild them
    # but it's not that easy because @gnosis.pm/safe-contracts does not come with Hardhat config.
    rm test/e2e/contractOrdersWithGnosisSafe.test.ts

    # Patch contracts for 0.8.x compatibility.
    # NOTE: I'm patching OpenZeppelin as well instead of installing OZ 4.0 because it requires less
    # work. The project imports files that were moved to different locations in 4.0.
    sed -i 's|uint256(-1)|type(uint256).max|g' src/contracts/GPv2Settlement.sol
    sed -i 's|return msg\.sender;|return payable(msg.sender);|g' node_modules/@openzeppelin/contracts/utils/Context.sol

    replace_version_pragmas

    for preset in $SELECTED_PRESETS; do
        hardhat_run_test "$config_file" "$preset" "${compile_only_presets[*]}" compile_fn test_fn "$config_var"
    done
}

external_test Gnosis-Protocol-V2 gp2_test
