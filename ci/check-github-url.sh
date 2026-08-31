# verify github url is correct
PATH_PARENT=$(basename "$PWD")
PATH_GRANDPARENT=$(basename "$(dirname "$PWD")")
echo "git url https://github.com/${PATH_GRANDPARENT}/${PATH_PARENT}.git"
