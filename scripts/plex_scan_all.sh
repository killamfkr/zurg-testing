#!/bin/bash

# Trigger a Plex library scan after TorBox Media Center refreshes its mount.
# TorBox Media Center does not expose zurg-style on_library_update hooks, so run
# this on a schedule (for example every 2 hours) or after you add new downloads.

plex_url="http://<url>" # If Plex runs in Docker on the same host, try http://172.17.0.1:32400
token="<token>" # Plex web UI dev console: window.localStorage.getItem("myPlexAccessToken")

curl -sLX GET "$plex_url/library/sections/all/refresh" -H "X-Plex-Token: $token"
echo "Requested Plex library scan for all sections"
