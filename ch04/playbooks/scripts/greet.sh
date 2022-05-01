#!/bin/bash
arg=$1

if [ -z "$arg" ]; then
  arg="script"
fi

echo "Hello $arg!"
