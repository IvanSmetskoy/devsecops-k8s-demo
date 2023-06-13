#!/bin/bash

#deptrack.sh

curl -X "POST" "http://10.219.1.201:8080/api/v1/bom" \
     -H 'Content-Type: multipart/form-data' \
     -H "X-Api-Key: eWXuuB6Wny5cZkZl3bQBIrRT8bOuexoW" \
     -F "projectName=NumericApp" \
     -F "bom=@target/bom.xml"