#!/bin/bash

if [ -z "$1" ];  then
  echo "  [!] No argument supplied, this script expects the project-env to run."
  exit 1
fi

projectEnv=$1
emptyLineReg="^\s+$"
emptyValueReg=".*?=($|\s*$)"

# Read the .env file
out=""
if [ -e .env ]; then
  for LINE in `cat .env`; do
    if [[ $LINE =~ $emptyLineReg ]]; then continue; fi
    if [[ $LINE =~ $emptyValueReg ]]; then continue; fi

    out+="$LINE
"
  done
  echo "  [+] .env contents added"
else
  echo "  [?] No .env found, skip..."
fi

# Read .env.prod file
if [ -e ".env.$projectEnv" ]; then
	for LINE in `cat .env.$projectEnv`; do
    if [[ $LINE =~ $emptyLineReg ]]; then continue; fi
    if [[ $LINE =~ $emptyValueReg ]]; then continue; fi

    out+="$LINE
"
	done
  echo "  [+] .env.$projectEnv contents added"
else
  echo "  [?] No .env.$projectEnv found, skip..."
fi

# Write the .env file
echo "$out" > .env
