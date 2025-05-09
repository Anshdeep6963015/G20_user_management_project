#!/bin/bash
for user in /home/*; do
    if [ -d "$user" ]; then
        sudo cp -a "$user/." /var/backups/g20_users/$(basename "$user")_backup_$(date '+%Y-%m-%d_%H-%M-%S')
    fi
done

