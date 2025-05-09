#!/bin/bash

LOG_FILE="/var/log/g20_user_management.log"

added=$(grep "User added:" "$LOG_FILE" | wc -l)
deleted=$(grep "User deleted:" "$LOG_FILE" | wc -l)
active=$((added - deleted))

echo "📊 G20 User Management Summary:"
echo "-------------------------------"
echo "🟢 Users added   : $added"
echo "🔴 Users deleted : $deleted"
echo "🟡 Active users  : $active"

