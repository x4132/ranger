#!/usr/bin/env fish

# Load environment variables from .env file
if test -f .env
    for line in (cat .env | grep -v '^#' | grep -v '^$')
        set -l key (echo $line | cut -d '=' -f 1)
        set -l value (echo $line | cut -d '=' -f 2-)
        set -gx $key $value
    end
else
    echo "Warning: .env file not found"
end
