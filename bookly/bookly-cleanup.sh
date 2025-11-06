#!/bin/bash


# Delete the bookly database 
cockroach sql --insecure --execute="DROP DATABASE bookly CASCADE;"

exit 0
