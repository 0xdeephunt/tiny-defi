# Tiny DeFi

## How to Run the Test

1.  Clone this repository:

    ```bash
    git clone https://github.com/0xdeephunt/tiny-defi.git
    cd tiny-defi
    ```

    Optional
    ```bash
    git submodule update --init --recursive
    ```

2. Build Docker Image:

    ```bash
    docker build -t foundry-dev:latest .
    ```

3. Start the Service:

    ```bash
    docker run -it --rm --name foundry-env -v ".:/app" -p 8545:8545 -p 3000:3000 foundry-dev:latest 
    ```

4. Verify Foundry version

    ```
    # forge --version
    forge Version: 1.2.3-stable
    Commit SHA: a813a2cee7dd4926e7c56fd8a785b54f32e0d10f
    Build Timestamp: 2025-06-08T15:42:40.147013149Z (1749397360)
    Build Profile: maxperf
    ```

5.  Install & Build

    Install
    ```bash
    forge install
    ```

    Build
    ```bash
    forge clean
    forge build
    ```

6.  Run a solution

    ```bash
    forge test --mp test/<module-name>/<ModuleName>.t.sol
    ```
    For example:
     ```bash
    forge test --mp test/uniswap-v2-core/UniswapV2Core.t.sol
    ```
    Run with log:
     ```bash
    forge test -vv --mp test/uniswap-v2-core/UniswapV2Core.t.sol
    ```