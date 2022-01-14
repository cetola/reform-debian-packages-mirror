#!/bin/bash

# clean up any existing processes
pkill -f 'python3.*compstat'

/usr/bin/python3 /usr/bin/reform-compstat.py -d 1 -i 0.3

