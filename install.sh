#!/bin/bash
set -e

if [ "$(uname)" = "Darwin" ]; then
    echo "Compiling macOS sleep watcher..."
    mkdir -p ~/.local/bin
    swiftc priv/mac_sleep_watcher.swift -o ~/.local/bin/eliterm_sleep_watcher
fi

echo "Installing Eliterm..."
mix deps.get
mix compile
mix escript.build

mkdir -p ~/.local/bin
cp bin/eliterm ~/.local/bin/eliterm
chmod +x ~/.local/bin/eliterm

# Add to PATH if not already there
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc
  echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.zshrc
  echo "Added ~/.local/bin to PATH. Please restart your shell or run: source ~/.bashrc"
fi

echo "Eliterm installed successfully!"
echo "Run 'eliterm' to get started."
