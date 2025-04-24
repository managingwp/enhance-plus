# This script sets up the environment for the project by adding the project's bin directory to the PATH variable.
# This should support bash and zsh
# Get script dir.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Add script dir to PATH.
export PATH="$SCRIPT_DIR:$SCRIPT_DIR/tools:$PATH"
