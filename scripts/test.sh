#!/bin/bash

. /appenv/bin/activate

pip download -d /build66666 -r requirements_test.txt --no-input

pip install --no-index -f /build66666 -r requirements_test.txt

exec $@ 
