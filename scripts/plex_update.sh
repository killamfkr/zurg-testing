#!/bin/bash

# PLEX PARTIAL SCAN script
# Use this for manual partial refreshes when you know which folder changed.

plex_url="http://<url>" # If Plex runs in Docker on the same host, try http://172.17.0.1:32400
token="<token>" # Plex web UI dev console: window.localStorage.getItem("myPlexAccessToken")
torbox_mount="/mnt/torbox" # replace with your TorBox mount path, ensure Plex sees the same path

section_ids=$(curl -sLX GET "$plex_url/library/sections" -H "X-Plex-Token: $token" | xmllint --xpath "//Directory/@key" - | grep -o 'key="[^"]*"' | awk -F'"' '{print $2}')

for arg in "$@"
do
    parsed_arg="${arg//\\}"
    echo "$parsed_arg"
    modified_arg="$torbox_mount/$parsed_arg"
    echo "Detected update on: $arg"
    echo "Absolute path: $modified_arg"

    for section_id in $section_ids
    do
        echo "Section ID: $section_id"
        curl -G -H "X-Plex-Token: $token" --data-urlencode "path=$modified_arg" "$plex_url/library/sections/$section_id/refresh"
    done
done

echo "All updated sections refreshed"
