
# publish to github
PATH_PARENT=$(basename "$PWD")
PATH_GRANDPARENT=$(basename "$(dirname "$PWD")")
CURRENT_VERSION=v1.0.0
find . -name ".DS_Store" -depth -exec rm {} \;
find . -exec touch {} \;
git add .;
git commit -m "checkpoint commit";
