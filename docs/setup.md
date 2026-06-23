# Setup

- Python prototype
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r python/requirements.txt

- Git LFS for videos (optional)
  brew install git-lfs    # macOS/homebrew
  git lfs install
  git lfs track "*.mp4"
  git add .gitattributes
