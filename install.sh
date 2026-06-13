#!/bin/bash
set -e

echo "Installing Eliterm..."
mix deps.get
mix compile
mix escript.build

mkdir -p ~/.local/bin
cp eliterm ~/.local/bin/eliterm
chmod +x ~/.local/bin/eliterm

# Add to PATH if not already there
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc
  echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.zshrc
  echo "Added ~/.local/bin to PATH. Please restart your shell or run: source ~/.bashrc"
fi

echo "Eliterm installed successfully!"
echo "Run 'eliterm' to get started."
