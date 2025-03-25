#!/bin/bash

# Function to set up Easy-RSA
setup_easyrsa() {
    echo "Setting up Easy-RSA..."
    mkdir -p ~/easy-rsa
    cp -r /usr/share/easy-rsa/* ~/easy-rsa/
    cd ~/easy-rsa
}

# Function with check for existing setup
setup_easyrsa_with_check() {
    echo
    echo "Step 2: Easy-RSA Setup"
    echo "━━━━━━━━━━━━━━━━━━━"
    echo "This step sets up the certificate authority infrastructure."
    echo "✓ This only needs to be done once per server."
    echo "✓ If you've already set up Easy-RSA before, you can skip this step."

    if [ -d ~/easy-rsa/pki ]; then
        echo "✓ Easy-RSA appears to be already set up with an existing PKI."
        if ! confirm_action "Do you want to set up Easy-RSA again? (This might overwrite existing certificates)"; then
            echo "Skipping Easy-RSA setup."
            return
        fi
    else
        if ! confirm_action "Do you want to set up Easy-RSA?"; then
            echo "Skipping Easy-RSA setup. Note that the script may fail without proper certificate infrastructure."
            return
        fi
    fi
    
    setup_easyrsa
}
